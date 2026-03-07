import Foundation

actor Explainer {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String, model: String = "claude-sonnet-4-6", maxTokens: Int = 4096) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    struct ExplanationResult {
        let levels: [String]  // 5 levels: Gist, Essentials, Mechanism, Nuance, Frontier
        let relatedTerms: [String]
        let searchPhrases: [String]  // search-optimized phrases, parallel to relatedTerms
    }

    private let maxInputLength = 8000

    func explain(text: String, context: String? = nil, followUp: String? = nil, onStreamToken: @escaping @Sendable (String) -> Void) async throws -> ExplanationResult {
        let templates = Config.loadPromptTemplate()

        // Truncate extremely long input to avoid context window issues
        let truncatedText = text.count > maxInputLength
            ? String(text.prefix(maxInputLength)) + "\n[...truncated]"
            : text

        let contextBlock: String
        if let context = context, !context.isEmpty {
            contextBlock = "\nContext: \(context)\n"
        } else {
            contextBlock = ""
        }

        let prompt: String
        if let followUp = followUp {
            prompt = templates.followUp
                .replacingOccurrences(of: "{{TEXT}}", with: truncatedText)
                .replacingOccurrences(of: "{{FOLLOWUP}}", with: followUp)
                .replacingOccurrences(of: "{{CONTEXT}}", with: contextBlock)
        } else {
            prompt = templates.standard
                .replacingOccurrences(of: "{{TEXT}}", with: truncatedText)
                .replacingOccurrences(of: "{{CONTEXT}}", with: contextBlock)
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplainerError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw ExplainerError.apiError(statusCode: 401, message: "Invalid API key. Check ~/.config/instant-explain/config.json")
        }

        if httpResponse.statusCode == 404 {
            throw ExplainerError.apiError(statusCode: 404, message: "Model not found — check the model name in ~/.config/instant-explain/config.json")
        }

        if httpResponse.statusCode == 429 {
            throw ExplainerError.apiError(statusCode: 429, message: "Rate limited — wait a moment and try again")
        }

        if httpResponse.statusCode == 529 {
            throw ExplainerError.apiError(statusCode: 529, message: "API overloaded — try again shortly")
        }

        guard httpResponse.statusCode == 200 else {
            throw ExplainerError.apiError(statusCode: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)")
        }

        var fullText = ""
        var streamedLength = 0
        var hitFirstDelimiter = false

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

                if !hitFirstDelimiter {
                    if fullText.contains("---LEVEL---") {
                        hitFirstDelimiter = true
                        let parts = fullText.components(separatedBy: "---LEVEL---")
                        let level3Only = parts[0]
                        let remaining = String(level3Only.dropFirst(streamedLength))
                        if !remaining.isEmpty {
                            onStreamToken(remaining)
                        }
                    } else {
                        let newContent = String(fullText.dropFirst(streamedLength))
                        if !newContent.isEmpty {
                            streamedLength = fullText.count
                            onStreamToken(newContent)
                        }
                    }
                }
            }
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
            remaining = String(remaining[..<relatedRange.lowerBound])
        }

        // Parse: first segment = Mechanism (level 3), then Gist, Essentials, Nuance, Frontier
        let segments = remaining.components(separatedBy: "---LEVEL---")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var levels = Array(repeating: "No explanation available.", count: 5)
        if segments.count >= 1 { levels[2] = segments[0] }  // Mechanism
        if segments.count >= 2 { levels[0] = segments[1] }  // The Gist
        if segments.count >= 3 { levels[1] = segments[2] }  // Essentials
        if segments.count >= 4 { levels[3] = segments[3] }  // Nuance
        if segments.count >= 5 { levels[4] = segments[4] }  // Frontier

        return ExplanationResult(levels: levels, relatedTerms: relatedTerms, searchPhrases: searchPhrases)
    }

    enum ExplainerError: LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Couldn't connect to the API. Check your internet connection."
            case .apiError(_, let msg):
                return msg
            case .parseError:
                return "Got an unexpected response. Try again."
            }
        }
    }
}
