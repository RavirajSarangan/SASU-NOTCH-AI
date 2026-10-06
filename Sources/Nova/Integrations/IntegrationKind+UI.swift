import NovaKit
import SwiftUI

extension IntegrationKind {
    var brand: BrandMark {
        switch self {
        case .github: .github
        case .vercel: .vercel
        case .n8n: .n8n
        case .supabase: .supabase
        case .stripe: .stripe
        case .firebase: .firebase
        }
    }

    var tokenHelp: (label: String, url: String) {
        switch self {
        case .github: ("Personal access token (classic: repo, notifications, workflow)", "https://github.com/settings/tokens")
        case .vercel: ("Vercel access token", "https://vercel.com/account/settings/tokens")
        case .n8n: ("n8n API key (Settings → n8n API)", "https://docs.n8n.io/api/authentication/")
        case .supabase: ("Supabase access token (sbp_…)", "https://supabase.com/dashboard/account/tokens")
        case .stripe: ("Restricted key with read-only access (rk_…)", "https://dashboard.stripe.com/apikeys")
        case .firebase: ("Uses your Google sign-in", "https://console.firebase.google.com")
        }
    }
}

extension ServiceHealth {
    var color: Color {
        switch self {
        case .healthy: Theme.success
        case .attention: Theme.warning
        case .failing: Theme.error
        case .unknown: Theme.textSecondary
        }
    }
}
