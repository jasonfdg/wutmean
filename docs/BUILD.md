# Instant Explain — Current Build

> **Version**: v3 (2026-03-07)
> **Status**: Working

## What It Does

Menu bar app. Select text anywhere, press F5, get streaming explanations at 5 complexity levels with terminal-aesthetic UI.

## Architecture

```
Sources/InstantExplain/
├── main.swift            # NSApp setup, .accessory activation policy
├── AppDelegate.swift     # Hotkey wiring, text selection (AX + CGEvent), streaming callbacks, menu
├── HotkeyListener.swift  # Carbon hotkey with dynamic key + double-tap support
├── Explainer.swift       # Anthropic streaming API, loads prompt, parses related terms
├── PopupPanel.swift      # Terminal-style floating panel, clickable nav, related concepts, action buttons
├── SettingsPanel.swift   # Settings UI: API key, model, level, hotkey recorder
└── Config.swift          # Config loader + prompt template loader + config save

Resources/
├── Info.plist            # App bundle metadata
└── default-prompt.md     # Default prompt template (copied to ~/.config on first run)
```

## How It Works

1. **F5 pressed** → Carbon hotkey fires → `handleHotkey()`
2. **Text grabbed** → Three-stage: AX API with context → CGEvent Cmd+C → Point-and-trigger (cursor words)
3. **Context extracted** → ~100 chars before/after selection passed as `{{CONTEXT}}` to LLM
4. **Popup shows** → `[ Mechanism ] 3/5` with empty body, tokens stream in live
5. **Stream completes** → All 5 levels parsed, arrow keys / clickable nav to switch
6. **Enter** → Terminal-style `> ` follow-up input → New streamed response
7. **Esc/F5/click "esc close"** → Dismiss

## 5 Levels (Pedagogically Refined)

Based on WIRED 5 Levels + SOLO Taxonomy + Feynman Technique research:

| Level | Name | Question Answered |
|-------|------|-------------------|
| 1 | The Gist | "What IS this?" — One analogy, 2-3 sentences |
| 2 | Essentials | "What does it do and why?" — Key terms defined |
| 3 | Mechanism | "How do the parts connect?" — Domain terms, cause-effect |
| 4 | Nuance | "Where does it break down?" — Edge cases, tradeoffs |
| 5 | Frontier | "What's debated?" — Peer conversation, open questions |

Each level is a **different conversation**, not just the same text with harder words.

## Build & Install

```bash
./install.sh
```

Does: `swift build -c release` → bundle to `/Applications/InstantExplain.app` → ad-hoc sign → reset TCC → install prompt template → launch.

## Config

`~/.config/instant-explain/config.json`:
```json
{
  "api_key": "sk-ant-...",
  "hotkey": "F5",
  "default_level": 3,
  "model": "claude-sonnet-4-6-20250514",
  "max_tokens": 4096
}
```

`~/.config/instant-explain/prompt.md`: Editable prompt template with `{{TEXT}}`, `{{CONTEXT}}`, and `{{FOLLOWUP}}` placeholders.

## Menu Bar

- **Edit Prompt...** → Opens prompt.md in default editor
- **Settings...** → Opens settings panel (API key, model, level, hotkey)
- **About** → Usage instructions
- **Test Explain** → Test with sample text
- **Quit**

## Settings Panel

Dark-themed settings window accessible from menu bar or gear icon in popup:
- **API Key**: Text field for Anthropic API key
- **Model**: Dropdown (Sonnet 4.6, Haiku 4.5, Opus 4.6)
- **Default Level**: Dropdown (1-5)
- **Hotkey**: Click-to-record button + double-tap checkbox
- Save persists to config.json and live-updates the app

## Popup Features

- **Related Concepts**: 3-4 clickable terms below the explanation, suggested by the LLM. Clicking triggers a new explanation.
- **Action Buttons**: [copy] [google] [wikipedia] [youtube] — copy current level text or search the original term.
- **Gear icon**: Opens settings panel directly from the popup.

## v2 Changes (from v1)

- Terminal-aesthetic: all monospaced fonts
- Clickable nav hints with hover glow
- Reliable keyboard input (NSEvent local monitor backup)
- Externalized prompt template (`~/.config/instant-explain/prompt.md`)
- Pedagogically-refined 5 levels (WIRED + SOLO + Feynman research)
- Terminal-style follow-up with `> ` prefix
- Settings/Edit Prompt menu items
- Expanded config: model, max_tokens, default_level, hotkey

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v1 | 2026-03-07 | Initial Swift rewrite. Carbon hotkey, AX+CGEvent text selection, streaming API, level-3-first UX, multi-monitor support. |
| v2 | 2026-03-07 | Terminal UX, clickable nav hints, keyboard fix, externalized prompts, pedagogical refinement, settings menu. |
| v3 | 2026-03-07 | Default model → Sonnet 4.6, surrounding context grab (AX), point-and-trigger (cursor words), {{CONTEXT}} prompt placeholder, settings UI panel (API key/model/level/hotkey recorder with double-tap), related concepts from LLM, action buttons (copy/google/wikipedia/youtube), gear icon in popup. |
