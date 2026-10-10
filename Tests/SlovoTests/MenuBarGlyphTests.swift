import XCTest
import AppKit
@testable import Slovo

/// The glyph of the menu bar icon: it does not move, it fits its canvas with room to spare at every pixel density, and it
/// is as large as the menu bar allows.
final class MenuBarGlyphTests: XCTestCase {
    /// The glyph drawn on a transparent canvas at `scale`, as it is for a screen of that pixel density: y down, black
    /// lines. Returns the alpha of every pixel, row by row from the top.
    private func render(_ glyph: MenuBarIcon.Glyph, scale: Int) -> (alpha: [UInt8], width: Int, height: Int) {
        let width = Int(MenuBarIcon.canvas.width) * scale, height = Int(MenuBarIcon.canvas.height) * scale
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        MenuBarIcon.draw(glyph, in: ctx)
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // The memory of a bitmap context starts with the top row of the image.
        return ((0..<width * height).map { data[$0 * 4 + 3] }, width, height)
    }

    /// The box around the pixels that are inked at all, in points of the canvas.
    private func box(_ glyph: MenuBarIcon.Glyph, scale: Int) -> CGRect {
        let (alpha, width, height) = render(glyph, scale: scale)
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] > 0 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, 0, "nothing is drawn")
        let s = CGFloat(scale)
        return CGRect(x: CGFloat(minX) / s, y: CGFloat(minY) / s,
                      width: CGFloat(maxX - minX + 1) / s, height: CGFloat(maxY - minY + 1) / s)
    }

    func testTheGlyphIsAsLargeAsTheMenuBarAllows() {
        XCTAssertEqual(MenuBarIcon.canvas.height, 22)
        for scale in [1, 2, 3] {
            let box = box(.done, scale: scale)
            // About 20 pt across, the mark of the family's icons scaled up from 14.
            XCTAssertGreaterThanOrEqual(box.width, 19.5, "scale \(scale)")
            XCTAssertLessThanOrEqual(box.width, MenuBarIcon.canvas.width, "scale \(scale)")
        }
    }

    func testNothingIsCutOffAtAnyDensityInAnyState() {
        let canvas = CGRect(origin: .zero, size: MenuBarIcon.canvas)
        for glyph in MenuBarIcon.Glyph.allCases {
            for scale in [1, 2, 3] {
                let box = box(glyph, scale: scale)
                // Inked pixels stay inside the canvas, with at least a pixel to spare above and below.
                XCTAssertTrue(canvas.insetBy(dx: 0, dy: 1 / CGFloat(scale)).contains(box), "\(glyph) at \(scale)x: \(box)")
                // And from 2x on the outermost pixel columns stay empty.
                if scale > 1 {
                    XCTAssertGreaterThan(box.minX, 0, "\(glyph) at \(scale)x")
                    XCTAssertLessThan(box.maxX, canvas.width, "\(glyph) at \(scale)x")
                }
            }
        }
    }

    func testTheLinesAreThickerInProportionToTheLargerMark() {
        // 1.18 pt on a mark 14 pt across before; the same share of 20 pt now.
        XCTAssertEqual(MenuBarIcon.Layout.lineWidth / MenuBarIcon.Layout.markWidth, 1.18 / 14, accuracy: 0.005)
    }

    func testTheStatesDifferAndStayTheSame() {
        let working = render(.working, scale: 2).alpha
        let done = render(.done, scale: 2).alpha
        let failed = render(.failed, scale: 2).alpha
        XCTAssertNotEqual(working, done, "the line is dashed while the word is not written")
        XCTAssertNotEqual(done, failed)
        // Nothing depends on the time: the glyph is drawn the same way every time.
        XCTAssertEqual(working, render(.working, scale: 2).alpha)
    }

    /// The pixel columns through the middle of every dash of the working line and of every break between two dashes.
    private func dashColumns(scale: Int) -> (dashes: [Int], breaks: [Int]) {
        typealias Layout = MenuBarIcon.Layout
        let period = Layout.dashLength + Layout.dashBreak + Layout.lineWidth
        let s = CGFloat(scale)
        let dashes = (0..<Layout.dashes).map { Int((Layout.middle + CGFloat($0) * period + Layout.dashLength / 2) * s) }
        let breaks = (0..<Layout.dashes - 1).map {
            Int((Layout.middle + CGFloat($0) * period + (Layout.dashLength + period) / 2) * s)
        }
        return (dashes, breaks)
    }

    func testTheWorkingLineIsDashedInPlainBlackAndAsThickAsTheWholeLine() {
        // The family's icons are strictly black and white: the line that is not written yet is a dashed line of the same
        // thickness, not a translucent one.
        for scale in [2, 3] {
            let (working, width, height) = render(.working, scale: scale)
            let done = render(.done, scale: scale).alpha
            func column(_ alpha: [UInt8], _ x: Int) -> [UInt8] { (0..<height).map { alpha[$0 * width + x] } }
            let columns = dashColumns(scale: scale)
            XCTAssertEqual(columns.dashes.count, MenuBarIcon.Layout.dashes)
            for x in columns.dashes {
                let profile = column(working, x)
                XCTAssertEqual(profile.max(), 255, "a dash is not fully black at \(scale)x, column \(x)")
                XCTAssertEqual(profile.max(), column(done, x).max())
                // As thick as the whole line: only the round ends of a short dash take a little off its corners.
                let ink = profile.reduce(0) { $0 + Int($1) }
                XCTAssertGreaterThanOrEqual(ink, Int(255 * MenuBarIcon.Layout.lineWidth * CGFloat(scale) * 0.95), "\(scale)x, column \(x)")
            }
            for x in columns.breaks {
                XCTAssertTrue(column(working, x).allSatisfy { $0 == 0 }, "the dashes touch at \(scale)x, column \(x)")
            }
        }
    }

    func testTheLineIsCentredOnItsPixelRows() {
        // Across the finished line the ink is the same above and below its middle, at every pixel density: the line is
        // as sharp as its thickness allows and not blurred to one side.
        for scale in [1, 2, 3] {
            let (alpha, width, height) = render(.done, scale: scale)
            let x = Int((MenuBarIcon.Layout.middle + MenuBarIcon.Layout.lineEnd) / 2 * CGFloat(scale))
            let profile = (0..<height).map { alpha[$0 * width + x] }
            let inked = profile.indices.filter { profile[$0] > 0 }
            let rows = Array(profile[inked.first!...inked.last!])
            XCTAssertEqual(rows, rows.reversed(), "the line is lopsided at \(scale)x: \(rows)")
            // At least as thick as the line is, in pixels.
            XCTAssertGreaterThanOrEqual(rows.reduce(0) { $0 + Int($1) }, Int(255 * MenuBarIcon.Layout.lineWidth * CGFloat(scale) * 0.98))
        }
    }
}
