import Combine
import Foundation
import Security
import StoreKit

private actor EntitlementRepository {
    private let service = "com.hgsldswk.scorekeep.entitlement"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "local-v1"]
    }

    func load() throws -> Entitlement {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return Entitlement() }
        guard status == errSecSuccess, let data = item as? Data else { throw ScoreError.storage }
        return try JSONDecoder().decode(Entitlement.self, from: data)
    }

    func save(_ value: Entitlement) throws {
        let data = try JSONEncoder().encode(value)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw ScoreError.storage }
        } else if status != errSecSuccess { throw ScoreError.storage }
    }
}

@MainActor final class StoreAccess: ObservableObject {
    static let proID = "com.hgsldswk.scorekeep.pro"
    static let trialID = "com.hgsldswk.scorekeep.trial"
    @Published private(set) var value = Entitlement()
    @Published private(set) var loaded = Launch.testing
    @Published private(set) var price: String?
    @Published private(set) var working = false
    @Published private(set) var productsLoading = false
    @Published private(set) var pending = false
    @Published private(set) var now = Date()
    @Published var message: String?
    private var products: [String: Product] = [:]
    private let repository = EntitlementRepository()
    private var starting = false
    private var refreshing = false
    private var dirty = false
    private var pendingProductID: String?

    var hasPro: Bool {
        if Launch.testing { return !Launch.has("-expired") || value.purchasedPro }
        return loaded && value.hasPro(at: now)
    }

    var mayClaimTrial: Bool { value.trialClaimedAt == nil && hasPro && !value.purchasedPro }

    func run() async {
        guard !Launch.testing, !starting else { return }
        starting = true
        do {
            let previous = try await repository.load()
            var initial = previous
            let date = Date()
            initial.proStartedAt = previous.proStartedAt ?? previous.firstOpen
            initial.latestSeen = max(date, previous.latestSeen ?? date)
            try await repository.save(initial)
            value = initial
            now = date
            loaded = true
        } catch { message = "error.storage" }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.listen() }
            group.addTask { await self.refresh() }
        }
    }

    private func listen() async {
        for await result in Transaction.updates {
            if case let .verified(transaction) = result { await record(transaction, finish: true) }
            else { message = "store.verification" }
        }
    }

    func refresh() async {
        guard loaded, !Launch.testing, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let date = Date()
        now = date
        var copy = value
        copy.latestSeen = max(date, copy.latestSeen ?? date)
        await persist(copy)
        for id in [Self.proID, Self.trialID] {
            if case let .verified(transaction)? = await Transaction.latest(for: id) {
                await record(transaction, finish: false)
            }
        }
    }

    func loadProducts() async {
        guard !Launch.testing, !productsLoading else { return }
        productsLoading = true
        defer { productsLoading = false }
        do {
            let items = try await Product.products(for: [Self.proID, Self.trialID])
            products = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            price = products[Self.proID]?.displayPrice
        } catch { message = "store.offline" }
    }

    func purchase(_ id: String) async {
        guard !working else { return }
        if Launch.testing {
            if id == Self.proID { value.purchasedPro = true }
            if id == Self.trialID { value.trialClaimedAt = Date() }
            return
        }
        guard loaded else { message = "error.storage"; return }
        working = true
        defer { working = false }
        message = nil
        if products[id] == nil { await loadProducts() }
        guard let product = products[id] else { message = "store.offline"; return }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)): await record(transaction, finish: true)
            case .success(.unverified): message = "store.verification"
            case .pending:
                pendingProductID = id
                pending = true
                message = "store.pending"
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = "store.offline" }
    }

    func restore() async {
        guard !Launch.testing, !working else { return }
        guard loaded else { message = "error.storage"; return }
        working = true
        defer { working = false }
        message = nil
        do {
            try await AppStore.sync()
            await refresh()
            if message == nil {
                message = value.purchasedPro ? "store.restored" : value.trialClaimedAt != nil ? "store.trialRestored" : "store.noPurchase"
            }
        } catch { message = "store.offline" }
    }

    private func record(_ transaction: Transaction, finish: Bool) async {
        guard loaded, [Self.proID, Self.trialID].contains(transaction.productID) else { return }
        var copy = value
        copy.applyVerified(trial: transaction.productID == Self.trialID,
                           originalDate: transaction.originalPurchaseDate, revoked: transaction.revocationDate != nil)
        guard await persist(copy) else { return }
        if pendingProductID == transaction.productID {
            pendingProductID = nil
            pending = false
            if message == "store.pending" { message = nil }
        }
        if finish {
            if transaction.productID == Self.trialID && transaction.revocationDate == nil { message = "store.trialClaimed" }
            await transaction.finish()
        }
    }

    @discardableResult private func persist(_ copy: Entitlement) async -> Bool {
        guard copy != value || dirty else { return true }
        value = copy
        dirty = true
        do {
            try await repository.save(copy)
            if value == copy { dirty = false }
            return true
        } catch {
            message = "error.storage"
            return false
        }
    }
}
