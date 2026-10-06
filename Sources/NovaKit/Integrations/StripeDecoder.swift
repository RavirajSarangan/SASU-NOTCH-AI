import Foundation

/// Stripe summary from a restricted read-only key. Only amounts, currency,
/// status and time are read; no card or customer data.
public enum StripeDecoder {
    public struct Payment: Sendable, Equatable {
        public var id: String
        public var amount: Int        // minor units
        public var currency: String
        public var status: String     // succeeded, pending, failed
        public var created: Date?
        public var refunded: Bool

        public init(id: String, amount: Int, currency: String, status: String, created: Date?, refunded: Bool) {
            self.id = id
            self.amount = amount
            self.currency = currency
            self.status = status
            self.created = created
            self.refunded = refunded
        }
    }

    static let zeroDecimal: Set<String> = ["bif", "clp", "djf", "gnf", "jpy", "kmf", "krw", "mga", "pyg", "rwf", "ugx", "vnd", "vuv", "xaf", "xof", "xpf"]

    /// Today's gross volume per currency from `GET /v1/balance_transactions`.
    public static func revenueByCurrency(_ data: Data) throws -> [String: Int] {
        var totals: [String: Int] = [:]
        for tx in try JSON.object(data)["data"] as? [[String: Any]] ?? [] {
            guard let type = tx["type"] as? String, type == "charge" || type == "payment",
                  let amount = tx["amount"] as? Int, let currency = tx["currency"] as? String else { continue }
            totals[currency, default: 0] += amount
        }
        return totals
    }

    public static func payments(_ data: Data) throws -> [Payment] {
        (try JSON.object(data)["data"] as? [[String: Any]] ?? []).map {
            Payment(id: $0["id"] as? String ?? UUID().uuidString, amount: $0["amount"] as? Int ?? 0,
                    currency: $0["currency"] as? String ?? "usd", status: $0["status"] as? String ?? "",
                    created: JSON.date($0["created"]), refunded: $0["refunded"] as? Bool ?? false)
        }
    }

    public static func format(minor amount: Int, currency: String) -> String {
        let code = currency.lowercased()
        let value = zeroDecimal.contains(code) ? Double(amount) : Double(amount) / 100
        return value.formatted(.currency(code: code.uppercased()))
    }

    public static func snapshot(revenue: [String: Int], payments: [Payment]) -> ServiceSnapshot {
        let main = revenue.max { $0.value < $1.value }
        let failed = payments.filter { $0.status == "failed" }
        return ServiceSnapshot(
            kind: .stripe,
            headline: main.map { format(minor: $0.value, currency: $0.key) } ?? "No sales today",
            detail: payments.first.map { "Last: \(format(minor: $0.amount, currency: $0.currency)) \($0.status)" } ?? "Today",
            health: failed.isEmpty ? .healthy : .attention,
            sections: [.init(title: "Recent payments", items: payments.prefix(10).map {
                ServiceItem(id: $0.id, title: format(minor: $0.amount, currency: $0.currency),
                            subtitle: $0.refunded ? "refunded" : $0.status,
                            health: $0.status == "succeeded" ? .healthy : ($0.status == "failed" ? .failing : .attention),
                            url: "https://dashboard.stripe.com/payments/\($0.id)", date: $0.created)
            })],
            webURL: "https://dashboard.stripe.com/dashboard"
        )
    }
}
