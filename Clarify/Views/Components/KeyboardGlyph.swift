import SwiftUI

struct KeyboardGlyph: View {
    let glyph: String
    @Environment(\.clarifyTheme) private var theme

    var body: some View {
        Text(glyph)
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(theme.tertiary.opacity(0.3), lineWidth: 0.5)
            )
    }
}
