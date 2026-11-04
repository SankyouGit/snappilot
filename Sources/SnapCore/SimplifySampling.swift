import CoreGraphics

/// Sample immediately outside a selected region; no screenshot mutation or upload.
public enum SimplifySampling {
    public static func surroundingColorHex(_ image: CGImage, region: CGRect) -> String {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = region.intersection(bounds)
        let strips = [CGRect(x: r.minX, y: r.minY - 3, width: r.width, height: 2),
                      CGRect(x: r.minX, y: r.maxY + 1, width: r.width, height: 2),
                      CGRect(x: r.minX - 3, y: r.minY, width: 2, height: r.height),
                      CGRect(x: r.maxX + 1, y: r.minY, width: 2, height: r.height)]
        var total = [Int](repeating: 0, count: 3), count = 0
        for strip in strips {
            guard let crop = ImageOps.crop(image, to: strip.intersection(bounds)) else { continue }
            var pixel = [UInt8](repeating: 0, count: 4)
            let success = pixel.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .high
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            if success && pixel[3] > 0 {
                for i in 0..<3 { total[i] += min(255, Int(pixel[i]) * 255 / Int(pixel[3])) }
                count += 1
            }
        }
        guard count > 0 else { return "#E5E7EB" }
        let digits = Array("0123456789ABCDEF")
        return "#" + total.map { value -> String in
            let v = value / count
            return String(digits[v / 16]) + String(digits[v % 16])
        }.joined()
    }
}
