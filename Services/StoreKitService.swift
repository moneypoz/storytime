import StoreKit

@MainActor
final class StoreKitService: ObservableObject {
    static let shared = StoreKitService()
    static let subscriptionGroupID = "com.storytime.allaccess"

    enum ProductID {
        static let monthly = "com.storytime.allaccess.monthly"
        static let forever  = "com.storytime.forever"
    }

    @Published var hasAllAccess = false
    @Published var isLoading = false
    @Published var monthlyProduct: Product?
    @Published var foreverProduct: Product?

    private var listenerTask: Task<Void, Error>?

    private init() {
        listenerTask = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let tx) = result { await tx.finish() }
                await self.refreshEntitlements()
            }
        }
        Task { await loadProducts(); await refreshEntitlements() }
    }

    func loadProducts() async {
        isLoading = true
        let fetched = try? await Product.products(for: [ProductID.monthly, ProductID.forever])
        monthlyProduct = fetched?.first { $0.id == ProductID.monthly }
        foreverProduct  = fetched?.first { $0.id == ProductID.forever }
        isLoading = false
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result {
                let valid = tx.productType == .nonConsumable
                         || (tx.expirationDate ?? .distantPast) > Date()
                if valid { active = true }
            }
        }
        hasAllAccess = active
    }

    func canPlay(book: Book) -> Bool {
        !book.isPremium || hasAllAccess
    }

    func purchase(product: Product) async throws {
        isLoading = true; defer { isLoading = false }
        let result = try await product.purchase()
        if case .success(let v) = result, case .verified(let tx) = v {
            await tx.finish()
            await refreshEntitlements()
        }
    }

    func restorePurchases() async {
        isLoading = true
        try? await AppStore.sync()
        await refreshEntitlements()
        isLoading = false
    }
}
