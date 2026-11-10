import CoreGraphics
import Foundation

/// Percentages of a display's usable area, measured from its top-left corner.
struct WindowLayout: Codable, Equatable, Sendable {
    var x: Double = 10
    var y: Double = 10
    var width: Double = 80
    var height: Double = 80

    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite)
            && x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 100 && y + height <= 100
    }

    func frame(in usableAXFrame: CGRect) throws -> CGRect {
        guard isValid else { throw WindowLayoutError.invalidLayout }
        return CGRect(x: usableAXFrame.minX + usableAXFrame.width * x / 100,
                      y: usableAXFrame.minY + usableAXFrame.height * y / 100,
                      width: usableAXFrame.width * width / 100,
                      height: usableAXFrame.height * height / 100)
    }
}

enum WindowLayoutError: LocalizedError {
    case invalidLayout, noPreviousFrame, noMinimizedWindow, noOtherScreen, frameNotApplied

    var errorDescription: String? {
        switch self {
        case .invalidLayout: return L10n.string("window.error.invalidLayout")
        case .noPreviousFrame: return L10n.string("window.error.noPreviousFrame")
        case .noMinimizedWindow: return L10n.string("window.error.noMinimizedWindow")
        case .noOtherScreen: return L10n.string("window.error.noOtherScreen")
        case .frameNotApplied: return L10n.string("window.error.frameNotApplied")
        }
    }
}

extension WindowLayout {
    private enum CodingKeys: String, CodingKey { case x, y, width, height }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        x = try values.decode(Double.self, forKey: .x)
        y = try values.decode(Double.self, forKey: .y)
        width = try values.decode(Double.self, forKey: .width)
        height = try values.decode(Double.self, forKey: .height)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid window layout percentages"))
        }
    }
}
