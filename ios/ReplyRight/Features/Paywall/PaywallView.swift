import ReplyRightCore
import ReplyRightUI
import StoreKit
import SwiftUI

/// ReplyRight Pro. Friendly, never pushy: the free plan stays useful.
///
/// Every price on this screen comes from StoreKit. Purchases go through the
/// App Store, and a purchase only counts once StoreKit has verified it.
struct PaywallView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let reason: PaywallReason

    @State private var selectedID: String = AppConfig.annualProductID
    @State private var message: String?
    @State private var isRestoring = false
    @State private var didPurchase = false

    var body: some View {
        NavigationStack {
            ScreenScroll {
                if didPurchase || app.isPro {
                    welcome
                } else {
                    offer
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.rrTextSecondary)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("paywall-close")
                }
            }
        }
        .task {
            if app.purchases.loadState != .loaded {
                await app.purchases.loadProducts()
            }
            if app.purchases.annual == nil, let first = app.purchases.products.first {
                selectedID = first.id
            }
        }
    }

    // MARK: Offer

    private var offer: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("ReplyRight Pro")
                EditorialTitle(reason.lead, emphasis: "Pro.", style: .display)
                Text(reason.detail)
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Benefit(
                    systemImage: "infinity",
                    title: "Keep going",
                    detail: "\(app.plans.pro.dailyGenerations) replies a day instead of \(app.plans.free.dailyGenerations)."
                )
                Benefit(
                    systemImage: "quote.opening",
                    title: "Every way to reply",
                    detail: "Ask them out, say how you feel, answer a dry message, and more."
                )
                Benefit(
                    systemImage: "graduationcap",
                    title: "A real conversation with your coach",
                    detail: "Room to talk things through, not just a few questions."
                )
                Benefit(
                    systemImage: "waveform",
                    title: "Sounds even more like you",
                    detail: "Learns from messages you've actually sent."
                )
                Benefit(
                    systemImage: "keyboard",
                    title: "More from the keyboard",
                    detail: "Replies and rewrites right where you type, as often as you need."
                )
            }
            .rrCard()

            plans

            if let message {
                Text(message)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(purchaseTitle) {
                purchase()
            }
            .buttonStyle(.rrPrimary)
            .disabled(selectedProduct == nil || app.purchases.isPurchasing)
            .accessibilityIdentifier("paywall-purchase")

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Text("Subscriptions renew automatically until cancelled. Cancel any time in Settings, at least 24 hours before the period ends. Payment is charged to your Apple Account.")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: RRSpace.m) {
                    Button(isRestoring ? "Restoring…" : "Restore purchases") {
                        restore()
                    }
                    .disabled(isRestoring)
                    Button("Terms") {
                        openURL(AppConfig.termsURL(base: app.apiBaseURL))
                    }
                    Button("Privacy") {
                        openURL(AppConfig.privacyURL(base: app.apiBaseURL))
                    }
                }
                .rrText(.footnote)
                .tint(Color.rrAccent)
            }

            Text("Not today? The free plan isn't going anywhere.")
                .rrText(.note)
                .foregroundStyle(Color.rrTextTertiary)
        }
    }

    @ViewBuilder
    private var plans: some View {
        switch app.purchases.loadState {
        case .idle, .loading:
            HStack(spacing: RRSpace.s) {
                ProgressView()
                Text("Getting today's prices…")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rrCard()

        case .unavailable:
            VStack(alignment: .leading, spacing: RRSpace.s) {
                Text("Plans aren't available right now.")
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
                Text("The App Store didn't return any plans. Check your connection and try again.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await app.purchases.loadProducts() }
                }
                .buttonStyle(.rrSecondaryCompact)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rrCard()

        case .loaded:
            VStack(spacing: RRSpace.xs) {
                if let annual = app.purchases.annual {
                    PlanRow(
                        title: "Yearly",
                        price: annual.displayPrice,
                        period: app.purchases.periodLabel(for: annual),
                        detail: yearlyDetail(annual),
                        badge: app.purchases.annualSavingsPercent.map { "Save \($0)%" },
                        isSelected: selectedID == annual.id
                    ) {
                        selectedID = annual.id
                        Haptics.select()
                    }
                    .accessibilityIdentifier("paywall-annual")
                }
                if let monthly = app.purchases.monthly {
                    PlanRow(
                        title: "Monthly",
                        price: monthly.displayPrice,
                        period: app.purchases.periodLabel(for: monthly),
                        detail: app.purchases.trialLabel(for: monthly),
                        badge: nil,
                        isSelected: selectedID == monthly.id
                    ) {
                        selectedID = monthly.id
                        Haptics.select()
                    }
                    .accessibilityIdentifier("paywall-monthly")
                }
            }
        }
    }

    private func yearlyDetail(_ annual: Product) -> String? {
        if let trial = app.purchases.trialLabel(for: annual) {
            return trial
        }
        if let perMonth = app.purchases.annualPricePerMonth {
            return "Works out to \(perMonth) a month"
        }
        return nil
    }

    private var selectedProduct: Product? {
        app.purchases.products.first { $0.id == selectedID }
    }

    private var purchaseTitle: String {
        if app.purchases.isPurchasing { return "One moment…" }
        guard let product = selectedProduct else { return "Continue" }
        if app.purchases.trialLabel(for: product) != nil {
            return "Start free trial"
        }
        return "Continue with \(product.displayPrice) \(app.purchases.periodLabel(for: product))"
    }

    private func purchase() {
        guard let product = selectedProduct else { return }
        message = nil
        Task {
            do {
                let outcome = try await app.purchases.purchase(product)
                switch outcome {
                case .purchased:
                    Haptics.success()
                    withAnimation(.rrGentle) {
                        didPurchase = true
                    }
                    await app.refresh(force: true)
                case .pending:
                    message = "Your purchase is waiting for approval. Pro will switch on as soon as it's confirmed."
                case .cancelled:
                    break
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func restore() {
        isRestoring = true
        message = nil
        Task {
            do {
                try await app.purchases.restore()
                if app.isPro {
                    Haptics.success()
                    withAnimation(.rrGentle) {
                        didPurchase = true
                    }
                    await app.refresh(force: true)
                } else {
                    message = "No active subscription was found for this Apple Account."
                }
            } catch {
                message = "Couldn't reach the App Store. Try again in a moment."
            }
            isRestoring = false
        }
    }

    // MARK: After purchase

    private var welcome: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            ScreenHeader(
                eyebrow: "You're in",
                lead: "Welcome to ",
                emphasis: "Pro.",
                subtitle: "Everything's unlocked. Thank you for backing ReplyRight. Now, where were we?"
            )
            Button("Back to it") {
                dismiss()
            }
            .buttonStyle(.rrPrimary)
            .accessibilityIdentifier("paywall-done")
        }
        .padding(.top, RRSpace.xl)
    }
}

private struct Benefit: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: RRSpace.m) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.rrAccent)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.rrAccentSoft)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
                Text(detail)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PlanRow: View {
    let title: String
    let price: String
    let period: String
    let detail: String?
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: RRSpace.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.rrAccent : Color.rrTextTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: RRSpace.xs) {
                        Text(title)
                            .rrText(.headline)
                            .foregroundStyle(Color.rrText)
                        if let badge {
                            Text(badge)
                                .rrText(.caption)
                                .foregroundStyle(Color.rrCoral)
                                .padding(.horizontal, RRSpace.xs)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.rrCoralSoft))
                        }
                    }
                    if let detail {
                        Text(detail)
                            .rrText(.footnote)
                            .foregroundStyle(Color.rrTextSecondary)
                    }
                }
                Spacer(minLength: RRSpace.xs)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(price)
                        .rrText(.headline)
                        .foregroundStyle(Color.rrText)
                    Text(period)
                        .rrText(.caption)
                        .foregroundStyle(Color.rrTextTertiary)
                }
            }
            .padding(RRSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                    .fill(isSelected ? Color.rrAccentSoft : Color.rrSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? Color.rrAccent.opacity(0.75) : Color.rrLine, lineWidth: 1)
            }
        }
        .buttonStyle(.rrPress)
        .accessibilityLabel("\(title), \(price) \(period)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
