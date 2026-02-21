import SwiftUI

struct MarkdownText: View {
    let markdown: String
    @Environment(\.clarifyTheme) private var theme

    var body: some View {
        Text(attributedContent)
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(theme.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedContent: AttributedString {
        do {
            return try AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            return AttributedString(markdown)
        }
    }
}
