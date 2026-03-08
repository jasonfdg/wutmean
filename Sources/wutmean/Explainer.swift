import Foundation

actor Explainer {
    private let provider: APIProvider
    private let apiKey: String
    private let model: String
    private let maxTokens: Int

    init(provider: APIProvider, apiKey: String, model: String, maxTokens: Int = 4096) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    struct ExplanationResult {
        let levels: [String]  // 3 levels: Plain, Technical, Examples
        let relatedTerms: [String]
        let searchPhrases: [String]
    }

    private let maxInputLength = 8000

    func explain(text: String, context: String? = nil, language: String = "English", onStreamToken: @escaping @Sendable (String) -> Void) async throws -> ExplanationResult {
        let template = Config.loadPromptTemplate()

        let truncatedText = text.count > maxInputLength
            ? String(text.prefix(maxInputLength)) + "\n[...truncated]"
            : text

        let contextBlock: String
        if let context = context, !context.isEmpty {
            contextBlock = "\n<context>\n\(context)\n</context>"
        } else {
            contextBlock = ""
        }

        let prompt = template
            .replacingOccurrences(of: "{{TEXT}}", with: truncatedText)
            .replacingOccurrences(of: "{{CONTEXT}}", with: contextBlock)
            .replacingOccurrences(of: "{{LANGUAGE}}", with: language)

        let request = try buildRequest(prompt: prompt)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw ExplainerError.networkError("No internet connection.")
            case .timedOut:
                throw ExplainerError.networkError("Request timed out. Try again.")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw ExplainerError.networkError("Can't reach the API. Check your connection.")
            default:
                throw ExplainerError.networkError("Network error: \(urlError.localizedDescription)")
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplainerError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw ExplainerError.apiError(statusCode: 401, message: "Invalid API key for \(provider.displayName). Update it in Settings.")
        }

        if httpResponse.statusCode == 404 {
            throw ExplainerError.apiError(statusCode: 404, message: "Model not found — check the model name in Settings.")
        }

        if httpResponse.statusCode == 429 {
            throw ExplainerError.apiError(statusCode: 429, message: "Rate limited — wait a moment and try again")
        }

        if httpResponse.statusCode == 529 {
            throw ExplainerError.apiError(statusCode: 529, message: "API overloaded — try again shortly")
        }

        guard httpResponse.statusCode == 200 else {
            throw ExplainerError.apiError(statusCode: httpResponse.statusCode, message: "\(provider.displayName) HTTP \(httpResponse.statusCode)")
        }

        let fullText: String
        switch provider {
        case .anthropic:
            fullText = try await streamAnthropic(bytes: bytes, onStreamToken: onStreamToken)
        case .openai:
            fullText = try await streamOpenAI(bytes: bytes, onStreamToken: onStreamToken)
        case .google:
            fullText = try await streamGoogle(bytes: bytes, onStreamToken: onStreamToken)
        }

        return parseResult(from: fullText)
    }

    // MARK: - Request building

    private func buildRequest(prompt: String) throws -> URLRequest {
        switch provider {
        case .anthropic:
            return try buildAnthropicRequest(prompt: prompt)
        case .openai:
            return try buildOpenAIRequest(prompt: prompt)
        case .google:
            return try buildGoogleRequest(prompt: prompt)
        }
    }

    private func buildAnthropicRequest(prompt: String) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        var request = URLRequest(url: provider.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60
        return request
    }

    private func buildOpenAIRequest(prompt: String) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        var request = URLRequest(url: provider.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60
        return request
    }

    private func buildGoogleRequest(prompt: String) throws -> URLRequest {
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "maxOutputTokens": maxTokens
            ]
        ]
        var components = URLComponents(url: provider.baseURL.appendingPathComponent("models/\(model):streamGenerateContent"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "alt", value: "sse")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60
        return request
    }

    // MARK: - Stream parsing

    private func streamAnthropic(bytes: URLSession.AsyncBytes, onStreamToken: @escaping @Sendable (String) -> Void) async throws -> String {
        var fullText = ""
        var streamedLength = 0
        var hitLevel1Close = false

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            if type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullText += text
                streamLevel1(fullText: fullText, streamedLength: &streamedLength, hitClose: &hitLevel1Close, onStreamToken: onStreamToken)
            }
        }

        return fullText
    }

    private func streamOpenAI(bytes: URLSession.AsyncBytes, onStreamToken: @escaping @Sendable (String) -> Void) async throws -> String {
        var fullText = ""
        var streamedLength = 0
        var hitLevel1Close = false

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }

            fullText += content
            streamLevel1(fullText: fullText, streamedLength: &streamedLength, hitClose: &hitLevel1Close, onStreamToken: onStreamToken)
        }

        return fullText
    }

    private func streamGoogle(bytes: URLSession.AsyncBytes, onStreamToken: @escaping @Sendable (String) -> Void) async throws -> String {
        var fullText = ""
        var streamedLength = 0
        var hitLevel1Close = false

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else { continue }

            fullText += text
            streamLevel1(fullText: fullText, streamedLength: &streamedLength, hitClose: &hitLevel1Close, onStreamToken: onStreamToken)
        }

        return fullText
    }

    // MARK: - Shared streaming logic

    /// Stream level_1 content live — shared across all providers
    private func streamLevel1(fullText: String, streamedLength: inout Int, hitClose: inout Bool, onStreamToken: @escaping @Sendable (String) -> Void) {
        if hitClose { return }

        if fullText.contains("</level_1>") {
            hitClose = true
            if let openRange = fullText.range(of: "<level_1>"),
               let closeRange = fullText.range(of: "</level_1>") {
                let rawContent = String(fullText[openRange.upperBound..<closeRange.lowerBound])
                let level1Content = String(rawContent.drop(while: { $0.isWhitespace || $0.isNewline }))
                let remaining = String(level1Content.dropFirst(streamedLength))
                if !remaining.isEmpty {
                    onStreamToken(remaining)
                }
            }
        } else if let openRange = fullText.range(of: "<level_1>") {
            let rawAfterOpen = String(fullText[openRange.upperBound...])
            let afterOpen = String(rawAfterOpen.drop(while: { $0.isWhitespace || $0.isNewline }))

            // Buffer potential partial XML tags
            var safeLength = afterOpen.count
            if let lastAngle = afterOpen.lastIndex(of: "<") {
                let trailing = afterOpen[lastAngle...]
                if !trailing.contains(">") {
                    safeLength = afterOpen.distance(from: afterOpen.startIndex, to: lastAngle)
                }
            }

            let safeContent = String(afterOpen.prefix(safeLength))
            let newContent = String(safeContent.dropFirst(streamedLength))
            if !newContent.isEmpty {
                streamedLength = safeContent.count
                onStreamToken(newContent)
            }
        }
    }

    // MARK: - Result parsing

    private func parseResult(from fullText: String) -> ExplanationResult {
        let levels = (1...3).map { i -> String in
            let openTag = "<level_\(i)>"
            let closeTag = "</level_\(i)>"
            guard let openRange = fullText.range(of: openTag),
                  let closeRange = fullText.range(of: closeTag) else {
                return "No explanation available."
            }
            return String(fullText[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Split off ---SEARCH--- section first (if present)
        var searchPhrases: [String] = []
        var remaining = fullText
        if let searchRange = remaining.range(of: "---SEARCH---") {
            let searchPart = String(remaining[searchRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            searchPhrases = searchPart
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            remaining = String(remaining[..<searchRange.lowerBound])
        }

        // Split off ---RELATED--- section
        var relatedTerms: [String] = []
        if let relatedRange = remaining.range(of: "---RELATED---") {
            let relatedPart = String(remaining[relatedRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            relatedTerms = relatedPart
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return ExplanationResult(levels: levels, relatedTerms: relatedTerms, searchPhrases: searchPhrases)
    }

    enum ExplainerError: LocalizedError {
        case invalidResponse
        case networkError(String)
        case apiError(statusCode: Int, message: String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Couldn't connect to the API. Check your internet connection."
            case .networkError(let detail):
                return detail
            case .apiError(_, let msg):
                return msg
            case .parseError:
                return "Got an unexpected response. Try again."
            }
        }
    }
}
