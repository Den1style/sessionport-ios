import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void
    @EnvironmentObject var settings: AppSettings
    @State private var step = 0

    private var steps: [OnboardingStep] {
        [
            OnboardingStep(icon: "keyboard",
                           title: L.t("onb.1.title"), body: L.t("onb.1.body"),
                           action: L.t("onb.next")),
            OnboardingStep(icon: "gear",
                           title: L.t("onb.2.title"), body: L.t("onb.2.body"),
                           action: L.t("onb.added")),
            OnboardingStep(icon: "arrow.left.arrow.right",
                           title: L.t("onb.3.title"), body: L.t("onb.3.body"),
                           action: L.t("onb.start")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Language switcher (top) — so users land on their language immediately
            HStack {
                Spacer()
                Picker("", selection: $settings.language) {
                    Text("EN").tag(AppLanguage.en)
                    Text("RU").tag(AppLanguage.ru)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .padding(.trailing, 20)
                .padding(.top, 12)
            }

            Spacer()

            let current = steps[step]

            VStack(spacing: 24) {
                Image(systemName: current.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 10) {
                    Text(current.title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text(current.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                if step == 1 {
                    Button(L.t("onb.openSettings")) {
                        let url = URL(string: "App-prefs:General&path=Keyboard/KEYBOARDS")
                            ?? URL(string: UIApplication.openSettingsURLString)!
                        UIApplication.shared.open(url)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
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
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 40)
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.3), value: step)
    }
}

private struct OnboardingStep {
    let icon: String
    let title: String
    let body: String
    let action: String
}
