import Foundation
import Observation
import ReplyRightCore
import StoreKit

/// Subscriptions with StoreKit 2.
///
/// - Products and prices always come from the App Store (or the local
///   `ReplyRight.storekit` file while testing). Nothing is hardcoded.
/// - Entitlement is derived from transactions StoreKit has verified on the
///   device. The signed transaction is also saved for the backend, which
///   verifies it again on its own. The app never tells the server "I am Pro".
@MainActor
@Observable
final class StoreService {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        /// The App Store returned no products (not configured yet, offline, or restricted).
        case unavailable
    }

    enum Outcome: Equatable {
        case purchased
        /// Waiting on something outside the app, such as Ask to Buy.
        case pending
        case cancelled
    }

    enum StoreError: LocalizedError {
        case unverified

        var errorDescription: String? {
            "The App Store couldn't verify that purchase. You haven't been charged for anything unverified. Please try again."
        }
    }

    private(set) var products: [Product] = []
    private(set) var loadState: LoadState = .idle
    private(set) var activeProductID: String?
    private(set) var expirationDate: Date?
    private(set) var isPurchasing = false

    private let store: SharedStore
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(store: SharedStore) {
        self.store = store
        // Show the last known state immediately; `refreshEntitlements` corrects it within moments.
        if let snapshot = store.loadEntitlement(), snapshot.isActive() {
            activeProductID = snapshot.productID
            expirationDate = snapshot.expiresAt
        }
        updatesTask = Task { [weak self] in
            // Renewals, refunds, and purchases approved outside the app arrive here.
            for await update in StoreKit.Transaction.updates {
                await self?.process(update)
            }
        }
    }

    var isPro: Bool { activeProductID != nil }

    var monthly: Product? { products.first { $0.id == AppConfig.monthlyProductID } }
    var annual: Product? { products.first { $0.id == AppConfig.annualProductID } }

    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: AppConfig.proProductIDs)
            products = loaded.sorted { $0.price < $1.price }
            loadState = loaded.isEmpty ? .unavailable : .loaded
        } catch {
            loadState = .unavailable
        }
    }

    func purchase(_ product: Product) async throws -> Outcome {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw StoreError.unverified
            }
            await transaction.finish()
            await refreshEntitlements()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Asks the App Store to sync purchases for this Apple Account. May prompt for sign-in.
    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    /// Recomputes Pro status from the transactions StoreKit currently vouches for.
    func refreshEntitlements() async {
        var best: StoreKit.Transaction?
        var bestToken: String?

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard AppConfig.proProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expires = transaction.expirationDate, expires < Date() { continue }

            let candidateExpiry = transaction.expirationDate ?? Date.distantFuture
            let currentExpiry = best?.expirationDate ?? Date.distantPast
            if best == nil || candidateExpiry > currentExpiry {
                best = transaction
                bestToken = result.jwsRepresentation
            }
        }

        if let best, let bestToken {
            activeProductID = best.productID
            expirationDate = best.expirationDate
            store.saveEntitlement(
                EntitlementSnapshot(jws: bestToken, productID: best.productID, expiresAt: best.expirationDate)
            )
        } else {
            activeProductID = nil
            expirationDate = nil
            store.saveEntitlement(nil)
        }
    }

    private func process(_ update: VerificationResult<StoreKit.Transaction>) async {
        if case .verified(let transaction) = update {
            await transaction.finish()
        }
        await refreshEntitlements()
    }

    // MARK: Presentation helpers (all derived from StoreKit, never hardcoded)

    /// "per month" or "per year" for a subscription product.
    func periodLabel(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day: return period.value == 7 ? "per week" : "every \(period.value) days"
        case .week: return period.value == 1 ? "per week" : "every \(period.value) weeks"
        case .month: return period.value == 1 ? "per month" : "every \(period.value) months"
        case .year: return period.value == 1 ? "per year" : "every \(period.value) years"
        @unknown default: return ""
        }
    }

    /// The annual plan's price expressed per month, formatted in the product's currency.
    var annualPricePerMonth: String? {
        guard let annual else { return nil }
        return (annual.price / 12).formatted(annual.priceFormatStyle)
    }

    /// How much the annual plan saves against twelve monthly payments, as a whole percentage.
    var annualSavingsPercent: Int? {
        guard let annual, let monthly else { return nil }
        let yearOfMonthly = monthly.price * 12
        guard yearOfMonthly > 0, annual.price < yearOfMonthly else { return nil }
        let fraction = (yearOfMonthly - annual.price) / yearOfMonthly
        let percent = NSDecimalNumber(decimal: fraction * 100).doubleValue
        let rounded = Int(percent.rounded())
        return rounded > 0 ? rounded : nil
    }

    /// A free-trial description when the product offers one, such as "7 days free".
    func trialLabel(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        return "\(period.value) \(unit) free"
    }

    var activePlanName: String? {
        guard let activeProductID else { return nil }
        if let product = products.first(where: { $0.id == activeProductID }) {
            return product.displayName
        }
        return activeProductID == AppConfig.annualProductID ? "ReplyRight Pro (annual)" : "ReplyRight Pro (monthly)"
    }
}
