import Foundation

struct Entitlement: Codable, Equatable {
    var firstOpen = Date()
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var purchasedPro = false
    var latestSeen: Date?
    var trialRevoked: Bool?

    var trialStart: Date { min(proStartedAt ?? firstOpen, trialClaimedAt ?? firstOpen) }
    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86_400) }

    mutating func applyVerified(trial: Bool, originalDate: Date, revoked: Bool) {
        if trial {
            trialClaimedAt = min(trialClaimedAt ?? originalDate, originalDate)
            trialRevoked = revoked
        } else {
            purchasedPro = !revoked
        }
    }

    func hasPro(at now: Date, free: Bool = Launch.isFree) -> Bool {
        free || purchasedPro || (trialRevoked != true && max(now, latestSeen ?? now) < trialEnd)
    }
}

struct ReviewProgress: Codable, Equatable {
    private(set) var useDays: Set<Date> = []
    private(set) var eligible = false
    private(set) var attemptedVersions: Set<String> = []

    mutating func recordUse(on date: Date, calendar: Calendar = .current) {
        useDays.insert(calendar.startOfDay(for: date))
    }

    mutating func completedEncounter() { eligible = useDays.count >= 3 || eligible }

    mutating func keepUsage(from current: Self) {
        useDays.formUnion(current.useDays)
        attemptedVersions.formUnion(current.attemptedVersions)
    }

    mutating func takeRequest(version: String, idle: Bool) -> Bool {
        guard idle, eligible else { return false }
        return attemptedVersions.insert(version).inserted
    }
}
