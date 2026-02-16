import SwiftUI

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        if #available(iOS 17, *) {
            Text(attributedMarkdown)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }

    private var attributedMarkdown: AttributedString {
        do {
            let attributed = try AttributedString(
                markdown: text,
                options: .init(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
            return attributed
        } catch {
            return AttributedString(text)
        }
    }
}
