import CoreGraphics
import Foundation

/// Builds `djvused` scripts that give DjVu pages a searchable, selectable text layer.
///
/// DjVu and PDF both put the origin at the bottom-left, so line frames only
/// need moving to the page origin and scaling from points to pixels.
enum DjVuTextLayer {
    static func script(page: Int, lines: [TextLine], mediaBox: CGRect, dpi: Int) -> String {
        let scale = CGFloat(dpi) / 72
        func pixels(_ value: CGFloat) -> Int { Int((value * scale).rounded()) }

        let zones = lines.map { line in
            let frame = line.frame.offsetBy(dx: -mediaBox.minX, dy: -mediaBox.minY)
            return " (line \(pixels(frame.minX)) \(pixels(frame.minY)) "
                + "\(pixels(frame.maxX)) \(pixels(frame.maxY)) \"\(escape(line.text))\")"
        }
        return "select \(page)\nset-txt\n"
            + "(page 0 0 \(pixels(mediaBox.width)) \(pixels(mediaBox.height))\n"
            + zones.joined(separator: "\n") + ")\n.\n"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
