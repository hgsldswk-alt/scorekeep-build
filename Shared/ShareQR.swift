import CoreGraphics
import CoreImage
import CoreGraphics
import CoreImage.CIFilterBuiltins
import Foundation

enum ShareQR {
    static func storeURL(_ appID: String) -> URL? {
        guard !appID.isEmpty, appID.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id" + appID)
    }

    static func image(for url: URL, scale: Int = 5) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let raw = filter.outputImage else { return nil }
        let margin: CGFloat = 4
        let positioned = raw.transformed(by: CGAffineTransform(translationX: margin, y: margin))
        let extent = CGRect(x: 0, y: 0, width: raw.extent.width + 2 * margin, height: raw.extent.height + 2 * margin)
        let padded = positioned.composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent))
        let output = padded.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        return CIContext().createCGImage(output, from: output.extent)
    }
}
