import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.circle")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Accessibility Access Required")
                .font(.headline)

            Text("Clarify needs accessibility permission to read selected text and detect your configured hotkey.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if appState.permissionManager.isAccessibilityGranted {
                Label("Access Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Access") {
                    appState.permissionManager.requestPermission()
                }
                .buttonStyle(.borderedProminent)

                ProgressView()
                    .scaleEffect(0.8)
                    .opacity(0.6)

                Text("Waiting for permission...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
