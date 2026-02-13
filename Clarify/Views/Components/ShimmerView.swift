import SwiftUI

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            shimmerLine(width: 0.92)
            shimmerLine(width: 0.75)
            shimmerLine(width: 0.55)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func shimmerLine(width fraction: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(width: Constants.panelWidth * fraction - 32, height: 10)
            .opacity(phase == 0 ? 0.35 : 0.65)
    }
}
