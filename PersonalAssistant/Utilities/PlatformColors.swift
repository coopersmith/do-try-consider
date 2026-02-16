import SwiftUI

extension Color {
    static var systemGray5Color: Color {
        #if canImport(UIKit)
        Color(UIColor.systemGray5)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var systemGray6Color: Color {
        #if canImport(UIKit)
        Color(UIColor.systemGray6)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}
