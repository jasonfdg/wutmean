# v2 Spec Anchor

## Goal
Evolve InstantExplain from a working prototype to a polished, terminal-aesthetic tool with reliable keyboard input, pedagogically-refined 5-level explanations loaded from an editable prompt file, a settings menu, and terminal-style follow-up UX.

## Functional Requirements

- **R1**: Keyboard input must work reliably — arrow keys, Esc, Enter, F5 must always respond when the popup is visible
- **R2**: Nav hints at the bottom must be clickable text (not buttons) that highlight on hover
- **R3**: All text (body, level label, nav hints, follow-up) must use monospaced font for terminal aesthetic
- **R4**: The 5-level explanation prompt must be loaded from an external markdown file (`~/.config/instant-explain/prompt.md`) that users can edit directly
- **R5**: Menu bar icon must include a Settings option that opens a settings window with: API key, hotkey, default level, model selection
- **R6**: Follow-up input must mimic terminal UX: `> ` prefix, monospaced, no visible border, green caret
- **R7**: Prompt must be pedagogically refined based on WIRED 5-levels + SOLO taxonomy research

## Non-Functional Requirements

- No new dependencies (pure Swift + AppKit)
- Keep 6-file structure (add new files only if needed for Settings)
- Maintain streaming-first UX from v1
- Config file backwards-compatible (new fields optional, old configs still work)

## Acceptance Criteria

- R1: With popup visible, arrow/Esc/Enter/F5 respond 100% of the time
- R2: Hovering nav hint text shows brightness change; clicking triggers action
- R3: All visible text in popup uses `.monospacedSystemFont`
- R4: Editing `~/.config/instant-explain/prompt.md` changes explanation output on next F5
- R5: Settings accessible from menu bar with functional hotkey/level/model/API fields
- R6: Follow-up field shows `> ` prefix and monospaced text
- R7: Each of the 5 levels produces a distinctly different *type* of explanation (not just vocabulary changes)

## Out of Scope

- Light mode / theme switching
- Custom window chrome / resizing
- Multiple API provider support
- Markdown rendering in body text (plain text only)
