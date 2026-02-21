import SwiftUI

struct ShimmerView: View {
    var stageText: String?

    @Environment(\.clarifyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()

    private static let barFractions: [CGFloat] = [0.92, 0.75, 0.55]
    private static let staggerStep: Double = 0.15
    private static let contentWidth: CGFloat = Constants.panelWidth - 32
    private static let cycleDuration: Double = 1.5

    var body: some View {
        Group {
            if reduceMotion {
                staticShimmer
            } else {
                animatedShimmer
            }
        }
        .accessibilityLabel("Loading explanation")
    }

    private var staticShimmer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.barFractions.enumerated()), id: \.offset) { _, fraction in
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.surface)
                    .frame(width: Self.contentWidth * fraction, height: 10)
            }

            if let stageText {
                Text(stageText)
                    .font(.caption2)
                    .foregroundStyle(theme.tertiary)
            }
        }
    }

    private var animatedShimmer: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(Self.barFractions.enumerated()), id: \.offset) { index, fraction in
                    let barElapsed = elapsed - Double(index) * Self.staggerStep
                    let t = barElapsed > 0
                        ? fmod(barElapsed, Self.cycleDuration) / Self.cycleDuration
                        : 0
                    // Ease-in-out per cycle for smoother feel
                    let phase = t < 0.5
                        ? 2 * t * t
                        : 1 - pow(-2 * t + 2, 2) / 2
                    ShimmerBar(barWidth: Self.contentWidth * fraction, phase: CGFloat(phase), theme: theme)
                }

                if let stageText {
                    Text(stageText)
                        .font(.caption2)
                        .foregroundStyle(theme.tertiary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: stageText)
                }
            }
        }
    }
}

private struct ShimmerBar: View {
    let barWidth: CGFloat
    let phase: CGFloat
    let theme: ClarifyTheme

    var body: some View {
        let bandWidth = barWidth * 0.4
        let travel = barWidth + bandWidth
        let offset = -bandWidth + travel * phase

        RoundedRectangle(cornerRadius: 4)
            .fill(theme.surface)
            .overlay(
                LinearGradient(
                    colors: [.clear, theme.shimmer, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth)
                .offset(x: offset - barWidth / 2)
                .clipped()
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(width: barWidth, height: 10)
    }
}
