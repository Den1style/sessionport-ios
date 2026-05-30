import StoreKit
import Foundation
import SwiftUI

private let kProProductID = "com.sessionport.app.pro.monthly"

@MainActor
final class StoreKitService: ObservableObject {

    static let shared = StoreKitService()

    @Published var isPro = false
    @Published var product: Product? = nil
    @Published var isLoading = false
    @Published var purchaseError: String? = nil

    private var updatesTask: Task<Void, Never>?

    private init() {
        isPro = SharedStorage.shared.isPro
        updatesTask = listenForTransactionUpdates()
        Task { await loadProduct() }
        Task { await checkCurrentEntitlement() }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Load product

    func loadProduct() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: [kProProductID])
            product = products.first
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product else { return }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                setProStatus(true)
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await checkCurrentEntitlement()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Entitlement check

    func checkCurrentEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == kProProductID,
               transaction.revocationDate == nil {
                setProStatus(true)
                return
            }
        }
        setProStatus(false)
    }

    // MARK: - Transaction updates listener

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        // Swift 6: Transaction.updates delivers on its own executor.
        // @MainActor isolation is re-entered via `await self.method()`.
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.checkCurrentEntitlement()
                }
            }
        }
    }

    private func setProStatus(_ value: Bool) {
        isPro = value
        SharedStorage.shared.isPro = value
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = StoreKitService.shared

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

                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "infinity", title: "Unlimited snapshots", subtitle: "No 5-snapshot limit")
                    FeatureRow(icon: "clock.arrow.circlepath", title: "Full history", subtitle: "Search and compare versions")
                    FeatureRow(icon: "arrow.triangle.2.circlepath", title: "Cross-device sync", subtitle: "iPhone, iPad, Mac")
                }
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    if let product = store.product {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            Group {
                                if store.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Start Pro — \(product.displayPrice)/mo")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(store.isLoading)
                    }

                    Button("Restore purchases") {
                        Task { await store.restorePurchases() }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Text("Cancel anytime. Subscription auto-renews monthly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: store.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .alert("Purchase Error", isPresented: Binding(
                get: { store.purchaseError != nil },
                set: { if !$0 { store.purchaseError = nil } }
            )) {
                Button("OK") { store.purchaseError = nil }
            } message: {
                Text(store.purchaseError ?? "")
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
                .foregroundStyle(.accentColor)
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
