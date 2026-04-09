import Foundation

struct BackendConfiguration {
    let supabaseURL: URL?
    let supabaseAnonKey: String
    let supabaseRedirectURL: URL?
    let batchUploadEndpoint: URL?
    let defaultExpensifyDestinationEmail: String

    var hasSupabaseAuth: Bool {
        supabaseURL != nil && !supabaseAnonKey.isEmpty
    }

    var hasLiveUpload: Bool {
        batchUploadEndpoint != nil
    }

    var uploadModeDescription: String {
        hasLiveUpload ? "Supabase batch upload" : "Demo upload mode"
    }

    static let current = load()

    private static func load(bundle: Bundle = .main) -> BackendConfiguration {
        guard
            let url = bundle.url(forResource: "BackendConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let values = plist as? [String: Any]
        else {
            return BackendConfiguration(
                supabaseURL: nil,
                supabaseAnonKey: "",
                supabaseRedirectURL: nil,
                batchUploadEndpoint: nil,
                defaultExpensifyDestinationEmail: ""
            )
        }

        let supabaseURL = (values["SupabaseURL"] as? String).flatMap(URL.init(string:))
        let redirectURL = (values["SupabaseRedirectURL"] as? String).flatMap(URL.init(string:))
        let batchUploadEndpoint = (values["BatchUploadEndpoint"] as? String).flatMap { value in
            value.isEmpty ? nil : URL(string: value)
        }

        return BackendConfiguration(
            supabaseURL: supabaseURL,
            supabaseAnonKey: values["SupabaseAnonKey"] as? String ?? "",
            supabaseRedirectURL: redirectURL,
            batchUploadEndpoint: batchUploadEndpoint,
            defaultExpensifyDestinationEmail: values["ExpensifyDestinationEmail"] as? String ?? ""
        )
    }
}
