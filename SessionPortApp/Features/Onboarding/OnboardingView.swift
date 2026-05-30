import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void
    @State private var step = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "keyboard",
            title: "Add the Keyboard",
            body: "SessionPort works as a custom keyboard that appears in Claude, ChatGPT, Gemini, and other AI apps.",
            action: "Next"
        ),
        OnboardingStep(
            icon: "gear",
            title: "Enable in Settings",
            body: "Go to Settings → General → Keyboard → Keyboards → Add New Keyboard → SessionPort.\n\nThen tap SessionPort and enable Full Access.",
            action: "I've added it"
        ),
        OnboardingStep(
            icon: "arrow.left.arrow.right",
            title: "Transfer Context",
            body: "Open Claude or ChatGPT, tap the globe icon to switch to SessionPort keyboard, and use ⚡ Simple or 🔬 Extended mode to save and load conversation context.",
            action: "Get started"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            let current = steps[step]

            VStack(spacing: 24) {
                Image(systemName: current.icon)
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 10) {
                    Text(current.title)
                        .font(.title.bold())

                    Text(current.body)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                // Open Settings button (step 1 only)
                if step == 1 {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }

                Button(current.action) {
                    if step < steps.count - 1 {
                        withAnimation { step += 1 }
                    } else {
                        onDone()
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .animation(.easeInOut(duration: 0.3), value: step)
    }
}

private struct OnboardingStep {
    let icon: String
    let title: String
    let body: String
    let action: String
}
