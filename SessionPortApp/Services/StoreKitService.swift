import Foundation
import SwiftUI

@MainActor
final class StoreKitService: ObservableObject {

    static let shared = StoreKitService()

    @Published var isPro = true
    @Published var isLoading = false
    @Published var purchaseError: String? = nil

    private init() {
        SharedStorage.shared.isPro = true
    }

    func loadProduct() async {}
    func purchase() async {}
    func restorePurchases() async {}
    func checkCurrentEntitlement() async {}
}

// MARK: - Paywall View

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    let reason: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 8) {
                    Text("⚡")
                        .font(.system(size: 52))
                    Text("SessionPort Pro")
                        .font(.title.bold())
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
