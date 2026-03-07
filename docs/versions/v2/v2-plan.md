# v2 Plan — Terminal UX, Externalized Prompts, Settings, Keyboard Fix

## Goal
Ship v2: terminal-aesthetic popup, reliable keyboard, pedagogically-refined prompts from external file, settings panel.

## Requirements → Tasks Mapping

| Req | Task(s) |
|-----|---------|
| R1 (keyboard fix) | T1 |
| R2 (clickable nav hints) | T2 |
| R3 (monospace terminal aesthetic) | T3 |
| R4 (external prompt file) | T4, T5 |
| R5 (settings menu) | T6, T7 |
| R6 (terminal follow-up) | T8 |
| R7 (refined prompts) | T4 |

## Tasks

### T1: Fix keyboard input reliability
**Files**: `PopupPanel.swift`
**Problem**: `keyDown(with:)` sometimes doesn't fire because the panel isn't actually the key window.
**Fix**: Add `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` as a backup handler that fires regardless of first responder status. Install it when the panel becomes visible, remove it when dismissed. This is a belt-and-suspenders approach — `keyDown` works when the panel is key, the local monitor works when it isn't.

### T2: Clickable nav hints with hover
**Files**: `PopupPanel.swift`
**Problem**: Nav hints are a static `NSTextField` — not clickable, no hover.
**Fix**: Replace the single `navHint` NSTextField with individual clickable labels. Each is an `NSTextField(labelWithString:)` with a tracking area for mouse hover. On hover: alpha goes from 0.45 → 0.7. On click: trigger the action. Use `NSTrackingArea` with `mouseEnteredAndExited` for hover detection. Layout them horizontally in a container view.

Actions: `← simpler` (left arrow), `harder →` (right arrow), `esc close` (dismiss), `⏎ follow-up` (toggle follow-up)

### T3: Monospace terminal aesthetic
**Files**: `PopupPanel.swift`
**Problem**: `bodyText` uses `.systemFont` — looks like a standard macOS dialog, not a terminal.
**Fix**: Change ALL text to `.monospacedSystemFont`:
- `bodyText.font` → `.monospacedSystemFont(ofSize: 13, weight: .regular)`
- `followUpField.font` → `.monospacedSystemFont(ofSize: 13, weight: .regular)`
- `followUpLabel` → monospaced
- Level label and nav hints already use monospaced (good)

### T4: Create external prompt template
**Files**: New file `~/.config/instant-explain/prompt.md` (created at runtime if missing)
**Also**: `Explainer.swift`, `Config.swift`

Create a prompt.md file with pedagogically-refined level definitions based on v2 research (WIRED 5 Levels + SOLO Taxonomy + Feynman Technique).

Key design principle: Each level answers a DIFFERENT question, not the same question with more words:
- Level 1 "The Gist": "What is this, in simplest terms?" — One analogy, 2-3 sentences, everyday words
- Level 2 "The Essentials": "What does this do and why does it matter?" — Key terms defined, short paragraph
- Level 3 "The Mechanism": "How do the parts connect?" — Domain terms, cause-effect, mechanisms
- Level 4 "The Nuance": "Where does the simple explanation break down?" — Edge cases, tradeoffs, limitations
- Level 5 "The Frontier": "What's debated and unresolved?" — Peer conversation, open questions, novel connections

### T5: Load prompt from file in Explainer
**Files**: `Explainer.swift`, `Config.swift`
- `Config` loads `prompt.md` from config dir, provides a default if file doesn't exist
- `Explainer.explain()` reads the prompt template and injects the selected text
- Template uses `{{TEXT}}` placeholder for the selected text and `{{FOLLOWUP}}` for follow-up questions

### T6: Expand Config with settings fields
**Files**: `Config.swift`
- Add fields: `hotkey` (String, default "F5"), `default_level` (Int, default 3), `model` (String), `max_tokens` (Int)
- Backwards compatible: missing fields use defaults
- `Config.load()` returns all fields

### T7: Settings menu in menu bar
**Files**: `AppDelegate.swift`
- Add "Settings..." menu item that opens `~/.config/instant-explain/` folder in Finder
- Add "Edit Prompt..." menu item that opens `prompt.md` in default text editor
- Add submenu showing current hotkey and default level
- Keep it simple — no custom settings window (that's over-engineering for a power-user tool)

### T8: Terminal-style follow-up input
**Files**: `PopupPanel.swift`
- Replace "Follow-up:" label with `> ` prefix (shell prompt style)
- Monospaced font (already covered by T3)
- Remove border from follow-up field
- Green text color for the `> ` prefix and caret

## Execution Order

1. T3 (monospace) — quickest, touches only fonts
2. T1 (keyboard fix) — critical bug fix
3. T2 (clickable nav hints) — depends on layout work
4. T8 (terminal follow-up) — quick UX change
5. T4 (create prompt.md) — new file, no code deps
6. T5 (load prompt in Explainer) — depends on T4
7. T6 (expand Config) — foundation for T7
8. T7 (settings menu) — depends on T6

## Verification

1. `./install.sh` builds and launches
2. F5 with text selected → popup appears, **keyboard always responds**
3. Nav hints glow on hover, click triggers action
4. All text is monospaced
5. Edit `~/.config/instant-explain/prompt.md` → next F5 uses new prompt
6. Menu bar → Settings opens config folder, Edit Prompt opens prompt.md
7. Follow-up shows `> ` prefix, monospaced, no border
8. Each level produces a distinctly different type of explanation
