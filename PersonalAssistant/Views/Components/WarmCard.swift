import SwiftUI

struct WarmCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(AppTheme.cardPadding)
            .background(AppTheme.adaptiveCard)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}
