import Foundation

enum APIProvider: String, Codable, CaseIterable {
    case anthropic
    case openai
    case google

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .google: return "Gemini"
        }
    }

    var placeholder: String {
        switch self {
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-..."
        case .google: return "AIza..."
        }
    }

    var baseURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .google: return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        }
    }

    var modelsURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/models")!
        case .openai: return URL(string: "https://api.openai.com/v1/models")!
        case .google: return URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        }
    }

    /// Prefixes used to filter relevant models from each provider's list endpoint
    var modelPrefixes: [String] {
        switch self {
        case .anthropic: return ["claude-"]
        case .openai: return ["gpt-4", "gpt-3.5", "o1", "o3", "o4"]
        case .google: return ["gemini-"]
        }
    }

    /// Detect provider from an API key string
    static func detect(key: String) -> APIProvider? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("sk-ant-") { return .anthropic }
        if trimmed.hasPrefix("sk-") { return .openai }
        if trimmed.hasPrefix("AIza") { return .google }
        return nil
    }

    /// Parse a multi-line key string into provider-key pairs
    static func detectAll(from keys: [String]) -> [(provider: APIProvider, key: String)] {
        keys.compactMap { key in
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let provider = detect(key: trimmed) else { return nil }
            return (provider, trimmed)
        }
    }

    /// Find the provider for a given model ID
    static func provider(forModel modelID: String) -> APIProvider? {
        for provider in allCases {
            if provider.modelPrefixes.contains(where: { modelID.hasPrefix($0) }) {
                return provider
            }
        }
        return nil
    }
}
