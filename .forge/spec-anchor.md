# Multi-Provider LLM Support

## Goal
Add Gemini and GPT model support alongside existing Anthropic, with auto-detection of providers from API keys and dynamic model fetching.

## Functional Requirements

- **R1: Multi-key input** — Settings UI replaces single API key field with a multi-line text area. User pastes keys one per line.
- **R2: Auto-detect provider** — App detects provider from key prefix: `sk-ant-` → Anthropic, `sk-` (not `sk-ant-`) → OpenAI, `AIza` → Google/Gemini. Shows detected provider badges below the text area.
- **R3: Dynamic model fetching** — On save, app fetches available models from each detected provider's list endpoint. Models cached to `~/.config/wutmean/models-cache.json`.
- **R4: Grouped model dropdown** — Model popup shows models grouped by provider with separator items. Only providers with valid keys appear.
- **R5: Multi-provider Explainer** — Explainer routes API calls to the correct provider endpoint based on selected model. Supports Anthropic, OpenAI, and Google streaming formats.
- **R6: Config migration** — Existing `api_key` string migrates to `api_keys` array on load. Backwards compatible.

## Non-Functional Requirements
- Streaming must work for all three providers (no blocking waits)
- Model fetch failures degrade gracefully (use cache or show error)
- Prompt template (XML tags) sent identically to all providers
- No new dependencies (pure Swift + AppKit)

## Acceptance Criteria
- AC1: Pasting an Anthropic + OpenAI key shows both provider badges and populates models from both
- AC2: Selecting a GPT model sends request to OpenAI endpoint with correct auth
- AC3: Selecting a Gemini model sends request to Google endpoint with correct auth
- AC4: Existing single-key configs auto-migrate without user action
- AC5: If a provider's model fetch fails, other providers still work
- AC6: Cached models load on startup when offline

## Out of Scope
- OpenRouter / proxy support
- Custom endpoint URLs
- Per-model prompt customization
- Token counting / cost tracking
