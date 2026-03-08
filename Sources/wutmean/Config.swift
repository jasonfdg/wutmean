import Foundation
import os.log

private let configLog = OSLog(subsystem: "com.chaukam.wutmean", category: "config")

struct Config {
    let apiKeys: [String]
    let hotkey: String
    let defaultLevel: Int
    let model: String
    let maxTokens: Int
    let hotkeyKeyCode: Int
    let hotkeyModifiers: Int
    let hotkeyDoubleTap: Bool
    let outputLanguage: String
    let darkMode: Bool
    let fontFamily: String
    let fontSize: Int

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/wutmean")
    private static let legacyConfigDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/instant-explain")
    static let configFile = configDir.appendingPathComponent("config.json")
    static let promptFile = configDir.appendingPathComponent("prompt.md")
    static let modelsCacheFile = configDir.appendingPathComponent("models-cache.json")

    /// Set to a warning message if the config file was corrupted on load
    static var loadWarning: String?

    /// Resolved provider-key pairs from apiKeys
    var providerKeys: [(provider: APIProvider, key: String)] {
        APIProvider.detectAll(from: apiKeys)
    }

    /// Get the API key for a specific provider
    func key(for provider: APIProvider) -> String? {
        providerKeys.first(where: { $0.provider == provider })?.key
    }

    static func load() -> Config {
        let json: [String: Any]
        if let data = try? Data(contentsOf: configFile) {
            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = parsed
                loadWarning = nil
            } else {
                os_log("Config file is corrupted, using defaults", log: configLog, type: .error)
                loadWarning = "Config file is corrupted. Using defaults.\nFix or delete: \(configFile.path)"
                json = [:]
            }
        } else {
            loadWarning = nil
            json = [:]
        }

        // Migration: api_key (string) → api_keys (array)
        let apiKeys: [String]
        if let keys = json["api_keys"] as? [String] {
            apiKeys = keys.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } else if let singleKey = json["api_key"] as? String, !singleKey.isEmpty {
            apiKeys = [singleKey]
        } else {
            apiKeys = []
        }

        return Config(
            apiKeys: apiKeys,
            hotkey: json["hotkey"] as? String ?? "F1",
            defaultLevel: json["default_level"] as? Int ?? 1,
            model: json["model"] as? String ?? "claude-sonnet-4-6",
            maxTokens: json["max_tokens"] as? Int ?? 4096,
            hotkeyKeyCode: json["hotkey_keycode"] as? Int ?? 122,  // kVK_F1
            hotkeyModifiers: json["hotkey_modifiers"] as? Int ?? 0,
            hotkeyDoubleTap: json["hotkey_double_tap"] as? Bool ?? true,
            outputLanguage: json["output_language"] as? String ?? "English",
            darkMode: json["dark_mode"] as? Bool ?? true,
            fontFamily: json["font_family"] as? String ?? "system-mono",
            fontSize: json["font_size"] as? Int ?? 12
        )
    }

    static func save(_ config: Config) {
        let dict: [String: Any] = [
            "api_keys": config.apiKeys,
            "hotkey": config.hotkey,
            "default_level": config.defaultLevel,
            "model": config.model,
            "max_tokens": config.maxTokens,
            "hotkey_keycode": config.hotkeyKeyCode,
            "hotkey_modifiers": config.hotkeyModifiers,
            "hotkey_double_tap": config.hotkeyDoubleTap,
            "output_language": config.outputLanguage,
            "dark_mode": config.darkMode,
            "font_family": config.fontFamily,
            "font_size": config.fontSize
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
        // Migrate from legacy instant-explain config
        if !fm.fileExists(atPath: configFile.path),
           fm.fileExists(atPath: legacyConfigDir.appendingPathComponent("config.json").path) {
            let legacyFiles = ["config.json", "prompt.md"]
            for file in legacyFiles {
                let src = legacyConfigDir.appendingPathComponent(file)
                let dst = configDir.appendingPathComponent(file)
                if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: src, to: dst)
                }
            }
        }
        if !fm.fileExists(atPath: configFile.path) {
            let template = #"{"api_keys": []}"# + "\n"
            try? template.write(to: configFile, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        }
        if !fm.fileExists(atPath: promptFile.path) {
            if let defaultPrompt = loadDefaultPrompt() {
                try? defaultPrompt.write(to: promptFile, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Models cache

    static func loadModelsCache() -> [String: [String]] {
        guard let data = try? Data(contentsOf: modelsCacheFile),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            return [:]
        }
        return dict
    }

    static func saveModelsCache(_ cache: [String: [String]]) {
        if let data = try? JSONSerialization.data(withJSONObject: cache, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: modelsCacheFile)
        }
    }

    // MARK: - Prompt

    static func loadPromptTemplate() -> String {
        let content: String
        if let userPrompt = try? String(contentsOf: promptFile, encoding: .utf8) {
            content = userPrompt
        } else if let defaultPrompt = loadDefaultPrompt() {
            content = defaultPrompt
        } else {
            return defaultStandardPrompt
        }

        let standard = content
            .components(separatedBy: "## Standard Explanation")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultStandardPrompt

        return standard
    }

    private static func loadDefaultPrompt() -> String? {
        if let url = Bundle.main.url(forResource: "default-prompt", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return nil
    }

    private static let defaultStandardPrompt = """
    Respond entirely in {{LANGUAGE}}.
    <keyword>{{TEXT}}</keyword>
    {{CONTEXT}}
    <instructions>
    Explain the keyword at three levels. Use the context only to determine the most relevant meaning and framing — never reference, quote, or acknowledge the context in your response (except to inform the domain and tone of Level 3's third example).
    Wrap each level in XML tags:
    <level_1>Plain language explanation. No jargon. 2-3 sentences max. One memorable anchor sentence.</level_1>
    <level_2>Fuller explanation with correct terminology and key distinctions. 3-4 sentences. Address one common misconception.</level_2>
    <level_3>Three examples that reveal the keyword's meaning. Format each as two parts separated by a line break: Line 1 is a sentence in double quotes; Line 2 is a plain unquoted explanation. Separate examples with a blank line. No numbering, headers, bold, or asterisks. (1) A vivid sentence using the keyword correctly + plain unpacking. (2) A near-miss that looks related but does NOT correctly use the keyword + why it misses. (3) A sentence in the same domain as the context + plain explanation. Let meaning emerge from examples, do not define first.</level_3>
    Do not add any text outside these tags, except for related concepts and search phrases below.
    </instructions>
    After all levels, output "---RELATED---" on its own line, followed by exactly 3 comma-separated related terms.
    After related terms, output "---SEARCH---" on its own line, followed by exactly 3 comma-separated search-optimized phrases (one per related term).
    """
}
