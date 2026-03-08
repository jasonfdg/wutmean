import Foundation
import os.log

private let fetchLog = OSLog(subsystem: "com.chaukam.wutmean", category: "model-fetch")

actor ModelFetcher {

    struct ProviderModels {
        let provider: APIProvider
        let models: [String]
    }

    /// Fetch available models from all detected providers in parallel
    func fetchAll(keys: [(provider: APIProvider, key: String)]) async -> [APIProvider: [String]] {
        var results: [APIProvider: [String]] = [:]

        await withTaskGroup(of: ProviderModels?.self) { group in
            for (provider, key) in keys {
                group.addTask {
                    do {
                        let models = try await self.fetchModels(provider: provider, key: key)
                        return ProviderModels(provider: provider, models: models)
                    } catch {
                        os_log("Failed to fetch models for %{public}@: %{public}@",
                               log: fetchLog, type: .error,
                               provider.displayName, error.localizedDescription)
                        return nil
                    }
                }
            }

            for await result in group {
                if let result {
                    results[result.provider] = result.models
                }
            }
        }

        // Save to cache
        let cacheDict = results.reduce(into: [String: [String]]()) { dict, entry in
            dict[entry.key.rawValue] = entry.value
        }
        Config.saveModelsCache(cacheDict)

        return results
    }

    /// Load cached models (for offline/startup)
    func loadCached() -> [APIProvider: [String]] {
        let cache = Config.loadModelsCache()
        var results: [APIProvider: [String]] = [:]
        for (key, models) in cache {
            if let provider = APIProvider(rawValue: key) {
                results[provider] = models
            }
        }
        return results
    }

    // MARK: - Per-provider fetch

    private func fetchModels(provider: APIProvider, key: String) async throws -> [String] {
        switch provider {
        case .anthropic: return try await fetchAnthropic(key: key)
        case .openai: return try await fetchOpenAI(key: key)
        case .google: return try await fetchGoogle(key: key)
        }
    }

    private func fetchAnthropic(key: String) async throws -> [String] {
        var request = URLRequest(url: APIProvider.anthropic.modelsURL)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.httpError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw FetchError.parseError
        }

        return dataArray
            .compactMap { $0["id"] as? String }
            .filter { id in APIProvider.anthropic.modelPrefixes.contains(where: { id.hasPrefix($0) }) }
            .sorted()
    }

    private func fetchOpenAI(key: String) async throws -> [String] {
        var request = URLRequest(url: APIProvider.openai.modelsURL)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.httpError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw FetchError.parseError
        }

        return dataArray
            .compactMap { $0["id"] as? String }
            .filter { id in APIProvider.openai.modelPrefixes.contains(where: { id.hasPrefix($0) }) }
            .sorted()
    }

    private func fetchGoogle(key: String) async throws -> [String] {
        var components = URLComponents(url: APIProvider.google.modelsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: key)]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.httpError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw FetchError.parseError
        }

        return models
            .compactMap { model -> String? in
                guard let name = model["name"] as? String else { return nil }
                // Google returns "models/gemini-2.5-pro" — strip prefix
                let id = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
                // Only include models that support content generation
                if let methods = model["supportedGenerationMethods"] as? [String],
                   methods.contains("generateContent") || methods.contains("streamGenerateContent") {
                    return id
                }
                return nil
            }
            .filter { id in APIProvider.google.modelPrefixes.contains(where: { id.hasPrefix($0) }) }
            .sorted()
    }

    enum FetchError: LocalizedError {
        case httpError
        case parseError

        var errorDescription: String? {
            switch self {
            case .httpError: return "API returned an error"
            case .parseError: return "Unexpected response format"
            }
        }
    }
}
