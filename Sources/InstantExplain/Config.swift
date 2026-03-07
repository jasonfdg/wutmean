import Foundation

struct Config {
    let apiKey: String
    let hotkey: String
    let defaultLevel: Int
    let model: String
    let maxTokens: Int
    let hotkeyKeyCode: Int
    let hotkeyModifiers: Int
    let hotkeyDoubleTap: Bool

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/instant-explain")
    static let configFile = configDir.appendingPathComponent("config.json")
    static let promptFile = configDir.appendingPathComponent("prompt.md")

    static func load() -> Config? {
        guard let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiKey = json["api_key"] as? String,
              !apiKey.isEmpty
        else {
            return nil
        }
        return Config(
            apiKey: apiKey,
            hotkey: json["hotkey"] as? String ?? "F5",
            defaultLevel: json["default_level"] as? Int ?? 3,
            model: json["model"] as? String ?? "claude-sonnet-4-6",
            maxTokens: json["max_tokens"] as? Int ?? 4096,
            hotkeyKeyCode: json["hotkey_keycode"] as? Int ?? 96,  // kVK_F5
            hotkeyModifiers: json["hotkey_modifiers"] as? Int ?? 0,
            hotkeyDoubleTap: json["hotkey_double_tap"] as? Bool ?? false
        )
    }

    static func save(_ config: Config) {
        let dict: [String: Any] = [
            "api_key": config.apiKey,
            "hotkey": config.hotkey,
            "default_level": config.defaultLevel,
            "model": config.model,
            "max_tokens": config.maxTokens,
            "hotkey_keycode": config.hotkeyKeyCode,
            "hotkey_modifiers": config.hotkeyModifiers,
            "hotkey_double_tap": config.hotkeyDoubleTap
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: configFile)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        }
    }

    static func ensureConfigExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir.path) {
            try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: configFile.path) {
            let template = #"{"api_key": ""}"# + "\n"
            try? template.write(to: configFile, atomically: true, encoding: .utf8)
            // Restrict permissions — API key stored in plaintext (M6)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        }
        if !fm.fileExists(atPath: promptFile.path) {
            if let defaultPrompt = loadDefaultPrompt() {
                try? defaultPrompt.write(to: promptFile, atomically: true, encoding: .utf8)
            }
        }
    }

    static func loadPromptTemplate() -> (standard: String, followUp: String) {
        let content: String
        if let userPrompt = try? String(contentsOf: promptFile, encoding: .utf8) {
            content = userPrompt
        } else if let defaultPrompt = loadDefaultPrompt() {
            content = defaultPrompt
        } else {
            return (standard: defaultStandardPrompt, followUp: defaultFollowUpPrompt)
        }

        let parts = content.components(separatedBy: "## Follow-Up")
        let standard = parts[0]
            .components(separatedBy: "## Standard Explanation")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultStandardPrompt
        let followUp = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : defaultFollowUpPrompt

        return (standard: standard, followUp: followUp)
    }

    private static func loadDefaultPrompt() -> String? {
        if let url = Bundle.main.url(forResource: "default-prompt", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return nil
    }

    private static let defaultStandardPrompt = """
    Explain the following text. Start with an Intermediate-level explanation and stream it directly.
    After the intermediate explanation, output exactly "---LEVEL---" on its own line, then provide the remaining 4 levels in order, each separated by "---LEVEL---":
    1. ELI5 (a child could understand)
    2. Beginner (high school level)
    3. Advanced (professional level)
    4. Expert (deep technical detail)
    Do NOT include level headers or labels. Just the explanation text for each level, separated by ---LEVEL---.
    Text to explain:
    \"\"\"""{{TEXT}}\"\"\"
    """

    private static let defaultFollowUpPrompt = """
    Original text the user selected:
    \"\"\"""{{TEXT}}\"\"\"
    The user has a follow-up question: {{FOLLOWUP}}
    Provide 5 levels of explanation for this follow-up. Start with Level 3, then output "---LEVEL---" and provide levels 1, 2, 4, 5.
    Do NOT include level headers or labels. Just the explanation text for each level, separated by ---LEVEL---.
    """
}
