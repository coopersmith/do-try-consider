import SwiftUI

extension View {
    @ViewBuilder
    func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func insetGroupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func warmScrollBackground() -> some View {
        #if os(iOS)
        self
            .scrollContentBackground(.hidden)
            .background(AppTheme.adaptiveBackground)
        #else
        self.background(AppTheme.adaptiveBackground)
        #endif
    }

    @ViewBuilder
    func warmListBackground() -> some View {
        #if os(iOS)
        self
            .scrollContentBackground(.hidden)
            .background(AppTheme.adaptiveBackground)
        #else
        self.background(AppTheme.adaptiveBackground)
        #endif
    }
}
