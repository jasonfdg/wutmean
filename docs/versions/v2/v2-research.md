# v2 Research Notes

## Bugs Identified in v1

### Keyboard Input Not Responding
The panel uses `keyDown(with:)` override but sometimes doesn't receive events. Root cause: NSPanel with `.nonactivatingPanel` style mask doesn't always become key window. The panel needs to be explicitly made first responder after activation. Additionally, `makeKeyAndOrderFront` + `NSApp.activate(ignoringOtherApps:)` race condition — the panel may not be key by the time `keyDown` fires.

**Fix**: Override `canBecomeKey` (already done) but also ensure the panel explicitly becomes the key window via `makeKey()` after `orderFront`. Consider using `NSEvent.addLocalMonitorForEvents` as backup keyboard handler since it works even if the panel isn't first responder.

### Nav Hints Not Interactive
Current `navHint` is a plain `NSTextField(labelWithString:)` — it's not clickable. Users expect clickable affordances.

## Pedagogical Research: 5 Levels of Explanation

### WIRED "5 Levels" Format (Source: WIRED YouTube Series)
Five audiences, each getting a fundamentally different conversation:
1. **Child (age ~7)**: Concrete analogies, physical metaphors, "it's like when you..."
2. **Teen (age ~14)**: Introduces proper terminology with definitions, cause-and-effect
3. **College student**: Assumes foundational knowledge, explains mechanisms
4. **Grad student**: Discusses edge cases, methodology, current debates
5. **Expert**: Peer conversation about frontiers, trade-offs, open problems

Key insight: "It's not a difference in explanation — it's a different conversation." Each level changes the *type* of engagement, not just vocabulary.

### SOLO Taxonomy (Biggs & Collis)
Academic framework for learning complexity:
1. **Prestructural**: No understanding, misses the point
2. **Unistructural**: One relevant aspect identified
3. **Multistructural**: Several aspects, but treated independently
4. **Relational**: Aspects integrated into a coherent whole
5. **Extended Abstract**: Generalized to new domains, creates new understanding

### Feynman Technique
Core principle: "Complexity and jargon often mask a lack of understanding." If you truly comprehend something, you can explain it without technical vocabulary. Four steps: select → teach to a child → identify gaps → simplify.

### Synthesis for Our 5 Levels
Combining WIRED + SOLO + Feynman into our prompt design:

| Level | Name | Audience Mental Model | Technique |
|-------|------|----------------------|-----------|
| 1 | ELI5 | No context at all | Concrete analogy, physical metaphor, 2-3 sentences |
| 2 | Beginner | Knows the domain exists | Introduce key terms with definitions, cause-effect chain |
| 3 | Intermediate | Has foundational knowledge | Explain the mechanism, how pieces fit together |
| 4 | Advanced | Working professional | Edge cases, trade-offs, why this approach vs alternatives |
| 5 | Expert | Peer in the field | Frontier questions, methodology critique, open problems |

Key design decision: Each level should feel like a **different conversation** (WIRED insight), not just the same text with harder words.

### Prompt Engineering for Multi-Level Output
- Specify audience explicitly per level (not just "simpler/harder")
- Use CO-STAR framework: Context, Objective, Style, Tone, Audience, Response
- Each level should use different cognitive verbs (SOLO): identify → list → relate → analyze → generalize
- The prompt should be externalized to a markdown file so users can edit it

## Terminal UX Design

### Monospace Everything
- Body text, level label, nav hints, follow-up field all use monospaced font
- Gives the "terminal" feeling — consistent character grid

### Interactive Nav Hints
- Replace static text with clickable elements
- Hover: subtle brightness increase (0.45 → 0.7 alpha)
- Click: trigger the action (left arrow, right arrow, esc, enter)
- Still looks like text, not buttons — terminal aesthetic

### Follow-Up as Terminal Input
- Prompt prefix: `> ` (like a shell prompt)
- Monospaced font, same as body
- Green cursor/caret color (terminal green)
- No visible border — just the `> ` prefix and blinking cursor

## Settings Design

### Config File Structure
Expand `~/.config/instant-explain/config.json`:
```json
{
  "api_key": "sk-ant-...",
  "hotkey": "F5",
  "default_level": 3,
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 4096,
  "theme": "dark"
}
```

### Menu Bar Settings
Accessible from the `?` menu bar icon:
- Settings... → opens config file in default editor (simplest approach)
- Or: inline menu items for common toggles
