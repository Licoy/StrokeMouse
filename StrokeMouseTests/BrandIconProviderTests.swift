import AppKit
import XCTest
@testable import StrokeMouse

@MainActor
final class BrandIconProviderTests: XCTestCase {
    func testMenuBarIconsUseOfficialPointSizeAndRenderingMode() {
        for style in MenuBarIconStyle.allCases {
            let image = BrandIconProvider.menuBarIcon(for: style)

            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertEqual(image.isTemplate, style == .monochrome)
        }
    }

    func testApplicationIconLoadsBundledBrandAsset() {
        let image = BrandIconProvider.applicationIcon()

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertFalse(image.isTemplate)
    }

    func testMenuBarIconStatusPrioritizesNeedPermissionOverPaused() {
        XCTAssertEqual(
            MenuBarIconStatus.resolve(isAccessibilityTrusted: false, isGesturesEnabled: true),
            .needPermission
        )
        XCTAssertEqual(
            MenuBarIconStatus.resolve(isAccessibilityTrusted: false, isGesturesEnabled: false),
            .needPermission
        )
        XCTAssertEqual(
            MenuBarIconStatus.resolve(isAccessibilityTrusted: true, isGesturesEnabled: false),
            .paused
        )
        XCTAssertEqual(
            MenuBarIconStatus.resolve(isAccessibilityTrusted: true, isGesturesEnabled: true),
            .normal
        )
    }

    func testStatusMenuBarIconsAreBakedNonTemplateBitmaps() {
        for status: MenuBarIconStatus in [.paused, .needPermission] {
            let image = BrandIconProvider.menuBarIcon(for: .monochrome, status: status)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertFalse(image.isTemplate, "Status tints must not be template (menu bar would discard color)")
            XCTAssertNotNil(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
    }

    func testPausedMenuBarIconContainsYellowishPixels() throws {
        let image = BrandIconProvider.menuBarIcon(for: .monochrome, status: .paused)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var foundTint = false
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.5
                else { continue }
                // systemYellow is strongly warm; accept a range for appearance variance.
                if color.redComponent > 0.55, color.greenComponent > 0.4, color.blueComponent < 0.45 {
                    foundTint = true
                    break
                }
            }
            if foundTint { break }
        }
        XCTAssertTrue(foundTint, "Paused icon should bake yellow into pixels")
    }

    func testApplicationIconUsesMacOSDockSafeArea() throws {
        let image = BrandIconProvider.applicationIcon()
        let occupancy = try opaqueOccupancy(of: image)

        XCTAssertGreaterThanOrEqual(occupancy, 0.79)
        XCTAssertLessThanOrEqual(occupancy, 0.83)
    }

    func testApplicationIconUsesSubtleNeutralBackgroundGradient() throws {
        let image = BrandIconProvider.applicationIcon()
        let bitmap = try bitmap(of: image)
        let firstBand = try averageNeutralLuminance(in: bitmap, yRange: 0.20 ... 0.35)
        let secondBand = try averageNeutralLuminance(in: bitmap, yRange: 0.65 ... 0.80)

        XCTAssertGreaterThan(abs(firstBand - secondBand), 0.025)
        XCTAssertGreaterThan(max(firstBand, secondBand), 0.97)
        XCTAssertLessThan(min(firstBand, secondBand), 0.95)
    }

    private func opaqueOccupancy(of image: NSImage) throws -> CGFloat {
        let bitmap = try bitmap(of: image)
        var bounds = NSRect.null

        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide
            where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.5 {
                bounds = bounds.union(NSRect(x: x, y: y, width: 1, height: 1))
            }
        }

        return max(
            bounds.width / CGFloat(bitmap.pixelsWide),
            bounds.height / CGFloat(bitmap.pixelsHigh)
        )
    }

    private func bitmap(of image: NSImage) throws -> NSBitmapImageRep {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: cgImage)
    }

    private func averageNeutralLuminance(
        in bitmap: NSBitmapImageRep,
        yRange: ClosedRange<CGFloat>
    ) throws -> CGFloat {
        let xRange = Int(CGFloat(bitmap.pixelsWide) * 0.20) ... Int(CGFloat(bitmap.pixelsWide) * 0.80)
        let rows = Int(CGFloat(bitmap.pixelsHigh) * yRange.lowerBound) ...
            Int(CGFloat(bitmap.pixelsHigh) * yRange.upperBound)
        var total: CGFloat = 0
        var count = 0

        for y in stride(from: rows.lowerBound, through: rows.upperBound, by: 4) {
            for x in stride(from: xRange.lowerBound, through: xRange.upperBound, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent >= 0.95,
                      color.saturationComponent <= 0.08
                else { continue }
                total += 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                count += 1
            }
        }

        return total / CGFloat(try XCTUnwrap(count > 0 ? count : nil))
    }
}
