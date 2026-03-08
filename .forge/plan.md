# Implementation Plan

## Task 1: APIProvider enum + key detection
**Files:** `Sources/wutmean/APIProvider.swift` (new)
- Enum with cases: `.anthropic`, `.openai`, `.google`
- `static func detect(key:) -> APIProvider?` — prefix matching
- Provider-specific constants: endpoint URLs, auth header names
- Model prefix filters per provider

## Task 2: Config migration — multi-key support
**Files:** `Sources/wutmean/Config.swift`
- Replace `apiKey: String` with `apiKeys: [String]`
- Migration: load `api_key` string → wrap in array
- Save writes `api_keys` array
- Add `models-cache.json` path
- Add `loadModelsCache()` / `saveModelsCache()` methods

## Task 3: Model fetching service
**Files:** `Sources/wutmean/ModelFetcher.swift` (new)
- Async function: `fetchModels(keys:) -> [APIProvider: [String]]`
- Anthropic: GET `api.anthropic.com/v1/models` → filter `claude-`
- OpenAI: GET `api.openai.com/v1/models` → filter `gpt-4`, `gpt-3.5`, `o1`, `o3`, `o4`
- Google: GET `generativelanguage.googleapis.com/v1beta/models?key=` → filter `gemini-`
- Cache results to disk, load cache on failure

## Task 4: Multi-provider Explainer
**Files:** `Sources/wutmean/Explainer.swift`
- Accept `provider: APIProvider` + `apiKey: String` in init or per-call
- `buildRequest(for:)` — provider-specific request construction
- `parseStreamToken(for:)` — provider-specific SSE/stream parsing
- Keep prompt template and XML extraction identical

## Task 5: Settings UI — multi-key + grouped dropdown
**Files:** `Sources/wutmean/SettingsPanel.swift`
- Replace NSSecureTextField with NSTextView (3-4 lines)
- Show/hide toggle for key masking
- Provider badge labels below text area
- Grouped NSPopUpButton with separators
- Fetch models on save, update dropdown

## Task 6: AppDelegate wiring
**Files:** `Sources/wutmean/AppDelegate.swift`
- Detect providers from config.apiKeys
- Create Explainer with correct provider+key for selected model
- Update on config change
