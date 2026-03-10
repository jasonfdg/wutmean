import Foundation

actor Explainer {
    private let provider: APIProvider
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let isCLIMode: Bool

    init(provider: APIProvider, apiKey: String, model: String, maxTokens: Int = 4096) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.isCLIMode = false
    }

    init(cliMode: Bool) {
        self.provider = .anthropic
        self.apiKey = ""
        self.model = ""
        self.maxTokens = 4096
        self.isCLIMode = cliMode
    }

    struct ExplanationResult {
        let levels: [String]  // 3 levels: Plain, Distill, Transfer
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

        if httpResponse.statusCode == 400 {
            // Read error body for details (e.g. unsupported parameter for reasoning models)
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            let detail = errorBody.isEmpty ? "Bad request" : errorBody.prefix(200)
            throw ExplainerError.apiError(statusCode: 400, message: "\(provider.displayName): \(detail)")
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
        // o-series reasoning models require max_completion_tokens instead of max_tokens
        let isReasoningModel = model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4")
        let tokensKey = isReasoningModel ? "max_completion_tokens" : "max_tokens"
        let body: [String: Any] = [
            "model": model,
            tokensKey: maxTokens,
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
        // Reasoning models think longer before streaming starts
        request.timeoutInterval = isReasoningModel ? 120 : 60
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
        // Gemini 2.5+ thinking models need more time for reasoning phase
        let isThinkingModel = model.contains("2.5") || model.contains("3.")
        request.timeoutInterval = isThinkingModel ? 120 : 60
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
                  let parts = content["parts"] as? [[String: Any]] else { continue }

            // Skip thinking parts from Gemini 2.5+ models (marked with "thought": true)
            for part in parts {
                if part["thought"] as? Bool == true { continue }
                guard let text = part["text"] as? String else { continue }
                fullText += text
            }
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

    // MARK: - Parallel explain (4 concurrent requests)

    func explainParallel(
        text: String,
        context: String? = nil,
        language: String = "English",
        onLevelToken: @escaping @Sendable (Int, String) -> Void,
        onLevelComplete: @escaping @Sendable (Int, String) -> Void,
        onMetaComplete: @escaping @Sendable ([String], [String]) -> Void
    ) async throws {
        let truncatedText = text.count > maxInputLength
            ? String(text.prefix(maxInputLength)) + "\n[...truncated]"
            : text

        let contextBlock: String
        if let context = context, !context.isEmpty {
            contextBlock = "\n<context>\n\(context)\n</context>"
        } else {
            contextBlock = ""
        }

        let useCLI = self.isCLIMode

        await withTaskGroup(of: Void.self) { group in
            for level in 0..<3 {
                group.addTask { [self] in
                    do {
                        try Task.checkCancellation()
                        let prompt = await self.buildLevelPrompt(level: level, text: truncatedText, context: contextBlock, language: language)
                        let tag = "level_\(level + 1)"

                        let fullText: String
                        if useCLI {
                            fullText = try await self.streamCLILevel(prompt: prompt, tag: tag) { token in
                                onLevelToken(level, token)
                            }
                        } else {
                            let request = try await self.buildRequest(prompt: prompt)
                            let (bytes, response) = try await URLSession.shared.bytes(for: request)

                            guard let httpResponse = response as? HTTPURLResponse,
                                  httpResponse.statusCode == 200 else {
                                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                                onLevelComplete(level, "API error (HTTP \(code))")
                                return
                            }

                            fullText = try await self.streamWithTag(bytes: bytes, tag: tag) { token in
                                onLevelToken(level, token)
                            }
                        }

                        let content = await self.extractTagContent(from: fullText, tag: tag)
                        onLevelComplete(level, content)
                    } catch is CancellationError {
                        // Cancelled — silent
                    } catch {
                        onLevelComplete(level, "")
                    }
                }
            }

            // Meta task (related terms + search phrases)
            group.addTask { [self] in
                do {
                    try Task.checkCancellation()
                    let prompt = await self.buildMetaPrompt(text: truncatedText, context: contextBlock, language: language)

                    let fullText: String
                    if useCLI {
                        fullText = try await self.collectCLIResponse(prompt: prompt)
                    } else {
                        let request = try await self.buildRequest(prompt: prompt)
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)

                        guard let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode == 200 else {
                            onMetaComplete([], [])
                            return
                        }

                        fullText = try await self.collectResponse(bytes: bytes)
                    }

                    let meta = await self.parseMetaResponse(from: fullText)
                    onMetaComplete(meta.relatedTerms, meta.searchPhrases)
                } catch is CancellationError {
                    // Cancelled
                } catch {
                    onMetaComplete([], [])
                }
            }
        }

        try Task.checkCancellation()
    }

    // MARK: - Generic SSE delta parsing

    private func parseSSEDelta(line: String) -> String? {
        switch provider {
        case .anthropic:
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { return nil }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "content_block_delta",
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String else { return nil }
            return text
        case .openai:
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { return nil }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { return nil }
            return content
        case .google:
            guard line.hasPrefix("data: ") else { return nil }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            var text = ""
            for part in parts {
                if part["thought"] as? Bool == true { continue }
                if let t = part["text"] as? String { text += t }
            }
            return text.isEmpty ? nil : text
        }
    }

    // MARK: - Generic tag-aware streaming

    private func streamWithTag(
        bytes: URLSession.AsyncBytes,
        tag: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        var fullText = ""
        var streamedLength = 0
        var hitClose = false

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let delta = parseSSEDelta(line: line) else { continue }
            fullText += delta
            streamTagContent(fullText: fullText, tag: tag, streamedLength: &streamedLength, hitClose: &hitClose, onToken: onToken)
        }

        return fullText
    }

    private func streamTagContent(
        fullText: String,
        tag: String,
        streamedLength: inout Int,
        hitClose: inout Bool,
        onToken: @escaping @Sendable (String) -> Void
    ) {
        if hitClose { return }

        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"

        if fullText.contains(closeTag) {
            hitClose = true
            if let openRange = fullText.range(of: openTag),
               let closeRange = fullText.range(of: closeTag) {
                let rawContent = String(fullText[openRange.upperBound..<closeRange.lowerBound])
                let content = String(rawContent.drop(while: { $0.isWhitespace || $0.isNewline }))
                let remaining = String(content.dropFirst(streamedLength))
                if !remaining.isEmpty { onToken(remaining) }
            }
        } else if let openRange = fullText.range(of: openTag) {
            let rawAfterOpen = String(fullText[openRange.upperBound...])
            let afterOpen = String(rawAfterOpen.drop(while: { $0.isWhitespace || $0.isNewline }))

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
                onToken(newContent)
            }
        }
    }

    private func collectResponse(bytes: URLSession.AsyncBytes) async throws -> String {
        var fullText = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let delta = parseSSEDelta(line: line) else { continue }
            fullText += delta
        }
        return fullText
    }

    // MARK: - Claude Code CLI streaming

    /// Build environment for claude CLI subprocess.
    /// Strips Claude Code session markers to avoid "nested session" errors.
    private static func cleanEnvironment() -> [String: String] {
        let blockedKeys: Set<String> = [
            "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT",
            "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
        ]
        return ProcessInfo.processInfo.environment.filter { !blockedKeys.contains($0.key) }
    }

    private static let claudeCLIPath: String = {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "claude"  // fallback to PATH
    }()

    private func streamCLILevel(
        prompt: String,
        tag: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.claudeCLIPath)
        process.arguments = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--max-turns", "1", "--model", "sonnet"]
        process.environment = Self.cleanEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw ExplainerError.networkError("Claude Code CLI not found. Install it from https://claude.ai/cli")
        }

        var fullText = ""
        var streamedLength = 0
        var hitClose = false

        let handle = pipe.fileHandleForReading
        for try await line in handle.bytes.lines {
            try Task.checkCancellation()

            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            // stream-json format: {"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}
            var text: String?
            if let type = json["type"] as? String,
               type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let t = delta["text"] as? String {
                text = t
            }
            // Fallback: direct text field
            if text == nil, let t = json["text"] as? String {
                text = t
            }

            guard let delta = text else { continue }
            fullText += delta
            streamTagContent(fullText: fullText, tag: tag, streamedLength: &streamedLength, hitClose: &hitClose, onToken: onToken)
        }

        process.waitUntilExit()
        if process.terminationStatus != 0 && fullText.isEmpty {
            throw ExplainerError.apiError(statusCode: Int(process.terminationStatus), message: "Claude CLI error (exit \(process.terminationStatus))")
        }

        return fullText
    }

    private func collectCLIResponse(prompt: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.claudeCLIPath)
        process.arguments = ["-p", prompt, "--output-format", "text", "--max-turns", "1", "--model", "sonnet"]
        process.environment = Self.cleanEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw ExplainerError.networkError("Claude Code CLI not found.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: text)
            }
        }
    }

    // MARK: - Parallel prompt builders

    private func buildLevelPrompt(level: Int, text: String, context: String, language: String) -> String {
        let tag = "level_\(level + 1)"
        let levelInstructions: String

        switch level {
        case 0:
            levelInstructions = """
            <\(tag)>
            Four paragraphs, each exactly one sentence. Separate each with a blank line. Do not combine or skip any.

            Paragraph 1 — Definition: State plainly what the keyword is. Start with "XYZ is..." or equivalent. No jargon, no hedging.

            Paragraph 2 — Insight: The sharpest, most precise thing you can say about this concept — what makes it distinct from adjacent concepts, or the thing most people miss when they first encounter it. One crisp sentence that makes the definition land.

            Paragraph 3 — Analogy: Draw a structural parallel to something the reader already knows from everyday life. The analogy should capture the underlying logic, not just surface resemblance. Make it specific to this concept, not a generic metaphor.

            Paragraph 4 — Stakes: Name one concrete situation where someone who misunderstands this makes a different — and worse — decision. Specific scenario, specific consequence — not "this matters because..."
            </\(tag)>
            """
        case 1:
            levelInstructions = """
            <\(tag)>
            The Distill. Two paragraphs, separated by a blank line. Do not combine or skip either.

            Paragraph 1 — One-liner: Compress the entire concept into a single memorable sentence — the kind you would write on a sticky note or text to a friend. Be vivid and specific, not abstract and safe. If the concept has a formula, law, or canonical phrasing, use it. Otherwise, create the sharpest compression you can — favor concrete language over academic language.

            Paragraph 2 — Origin: In one sentence, explain why this concept was invented or named — the specific problem, observation, or moment that forced it into existence. Not a history lesson. The origin story that makes the concept feel inevitable rather than arbitrary.
            </\(tag)>
            """
        case 2:
            levelInstructions = """
            <\(tag)>
            The Transfer. Three one-sentence analogies showing the same concept at work in three different domains.

            Before writing any analogy, internally decompose the keyword into its causal structure:
            (a) What specific causal chain makes this concept work?
            (b) What constraint or tension is essential?
            (c) Why does this mechanism produce THIS outcome and not a different one?
            Do not output this decomposition.

            Each of the three analogies must capture a DIFFERENT part of the causal structure. Format each as exactly two lines separated by a line break:
            — Line 1: A single sentence in a specific domain, using vivid concrete details. Begin immediately — no label, no colon, no dash, no bold text.
            — Line 2: One sentence naming the exact shared causal mechanism as a process, not a category.

            Separate the three analogies with a blank line. No numbering, no labels, no bold text, no headers, no asterisks.
            Choose three genuinely different domains. At least one from everyday life.
            </\(tag)>
            """
        default:
            levelInstructions = ""
        }

        return """
        Respond entirely in \(language).

        <keyword>\(text)</keyword>\(context)

        <instructions>
        Explain the keyword. Use the context only to determine the most relevant meaning and domain — never reference, quote, or acknowledge the context in your response.

        Wrap your response in <\(tag)> tags. No markdown formatting anywhere (no bold, no bullets, no headers, no asterisks). Plain prose only.

        \(levelInstructions)

        Output only the <\(tag)> tags and content. Nothing else.
        </instructions>
        """
    }

    private func buildMetaPrompt(text: String, context: String, language: String) -> String {
        """
        Respond entirely in \(language).

        <keyword>\(text)</keyword>\(context)

        Output "---RELATED---" on its own line, followed by exactly 3 comma-separated related terms that would meaningfully deepen understanding of this keyword — real conceptual next steps, not adjacent vocabulary.

        After the related terms, output "---SEARCH---" on its own line, followed by exactly 3 comma-separated search-optimized phrases (one per related term, same order). Each should be 4-6 words that return useful Google/YouTube results — include domain context.

        Output only these two sections. Nothing else.
        """
    }

    private func extractTagContent(from fullText: String, tag: String) -> String {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"
        guard let openRange = fullText.range(of: openTag),
              let closeRange = fullText.range(of: closeTag) else {
            return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(fullText[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseMetaResponse(from fullText: String) -> (relatedTerms: [String], searchPhrases: [String]) {
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

        var relatedTerms: [String] = []
        if let relatedRange = remaining.range(of: "---RELATED---") {
            let relatedPart = String(remaining[relatedRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            relatedTerms = relatedPart
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return (relatedTerms: relatedTerms, searchPhrases: searchPhrases)
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
