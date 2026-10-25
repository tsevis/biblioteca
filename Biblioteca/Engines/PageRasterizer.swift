import CoreGraphics
import Foundation
import PDFKit

/// Renders PDF pages to the image formats DjVuLibre's encoders read:
/// colour PPM (P6) for `c44` and black-and-white PBM (P4) for `cjb2`.
enum PageRasterizer {
    /// Grey level below which a pixel counts as ink in black-and-white output.
    private static let inkThreshold: UInt8 = 160

    static func writePPM(of page: PDFPage, dpi: Int, to url: URL) throws {
        let context = try render(page, dpi: dpi, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        let (width, height, rowBytes) = (context.width, context.height, context.bytesPerRow)
        let source = try pixels(of: context)
        let bytes = [UInt8](unsafeUninitializedCapacity: width * height * 3) { buffer, count in
            for row in 0..<height {
                for column in 0..<width {
                    let from = row * rowBytes + column * 4
                    let to = (row * width + column) * 3
                    buffer[to] = source[from]
                    buffer[to + 1] = source[from + 1]
                    buffer[to + 2] = source[from + 2]
                }
            }
            count = width * height * 3
        }
        try (Data("P6\n\(width) \(height)\n255\n".utf8) + Data(bytes)).write(to: url)
    }

    static func writePBM(of page: PDFPage, dpi: Int, to url: URL) throws {
        let context = try render(page, dpi: dpi, space: CGColorSpaceCreateDeviceGray(),
                                 bitmapInfo: CGImageAlphaInfo.none.rawValue)
        let (width, height, rowBytes) = (context.width, context.height, context.bytesPerRow)
        let source = try pixels(of: context)
        let packedRow = (width + 7) / 8
        // PBM rows are packed eight pixels per byte, most significant bit first, 1 = black.
        let bytes = [UInt8](unsafeUninitializedCapacity: packedRow * height) { buffer, count in
            buffer.initialize(repeating: 0)
            for row in 0..<height {
                for column in 0..<width where source[row * rowBytes + column] < inkThreshold {
                    buffer[row * packedRow + column / 8] |= 0x80 >> UInt8(column % 8)
                }
            }
            count = packedRow * height
        }
        try (Data("P4\n\(width) \(height)\n".utf8) + Data(bytes)).write(to: url)
    }

    private static func render(_ page: PDFPage, dpi: Int, space: CGColorSpace,
                               bitmapInfo: UInt32) throws -> CGContext {
        let bounds = page.bounds(for: .mediaBox)
        let scale = CGFloat(dpi) / 72
        let rotated = page.rotation % 180 != 0
        let width = Int((rotated ? bounds.height : bounds.width) * scale)
        let height = Int((rotated ? bounds.width : bounds.height) * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
        else { throw ConversionError.unreadableDocument("page \(page.label ?? "?")") }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context
    }

    private static func pixels(of context: CGContext) throws -> UnsafePointer<UInt8> {
        guard let data = context.data else {
            throw ConversionError.unreadableDocument("rendered page")
        }
        return UnsafePointer(data.assumingMemoryBound(to: UInt8.self))
    }
}
