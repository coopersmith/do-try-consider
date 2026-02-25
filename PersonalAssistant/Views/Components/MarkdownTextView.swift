import SwiftUI

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block Types

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case bulletItem(text: String)
        case numberedItem(number: String, text: String)
        case codeBlock(code: String)
        case divider
    }

    // MARK: - Parsing

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line — skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Divider (--- or ***)
            if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == " " })
                && trimmed.filter({ $0 == "-" || $0 == "*" }).count >= 3 {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Code block
            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(code: codeLines.joined(separator: "\n")))
                continue
            }

            // Heading
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                if level <= 6 {
                    let headingText = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: level, text: headingText))
                    i += 1
                    continue
                }
            }

            // Bullet list item
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                let itemText = String(trimmed.dropFirst(2))
                blocks.append(.bulletItem(text: itemText))
                i += 1
                continue
            }

            // Numbered list item
            if let match = trimmed.range(of: #"^(\d+[\.\)])\s+"#, options: .regularExpression) {
                let prefix = String(trimmed[match]).trimmingCharacters(in: .whitespaces)
                let itemText = String(trimmed[match.upperBound...])
                blocks.append(.numberedItem(number: prefix, text: itemText))
                i += 1
                continue
            }

            // Paragraph — collect consecutive non-special lines
            var paragraphLines: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("#") || next.hasPrefix("- ") || next.hasPrefix("* ")
                    || next.hasPrefix("• ") || next.hasPrefix("```") || next.range(of: #"^\d+[\.\)]"#, options: .regularExpression) != nil {
                    break
                }
                paragraphLines.append(next)
                i += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineMarkdown(text)
                .font(headingFont(level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 2)

        case .paragraph(let text):
            inlineMarkdown(text)
                .foregroundStyle(AppTheme.textSecondary)

        case .bulletItem(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundStyle(AppTheme.textSecondary)
                inlineMarkdown(text)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.leading, 4)

        case .numberedItem(let number, let text):
            HStack(alignment: .top, spacing: 4) {
                Text(number)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(minWidth: 20, alignment: .trailing)
                inlineMarkdown(text)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.leading, 4)

        case .codeBlock(let code):
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.adaptiveSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))

        case .divider:
            Divider()
        }
    }

    private func inlineMarkdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return AppTheme.title3Font
        case 2: return AppTheme.headlineFont
        default: return AppTheme.subheadlineFont
        }
    }
}
