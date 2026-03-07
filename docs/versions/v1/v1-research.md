# v1 Research Notes

## Background

Started as a Python app (pynput + pyobjc + tkinter), then rewrote to native Swift for proper macOS integration.

## Key Findings

### Why Swift over Python
- Python `pynput` global hotkeys unreliable on macOS
- Tkinter popup looks foreign on macOS, no proper dark mode
- pyobjc Accessibility bindings are fragile
- Swift app bundle required for: Accessibility permissions, LSUIElement (menu bar only), SMAppService (login item)

### Hotkey: Carbon > NSEvent > CGEventTap
- **Carbon `RegisterEventHotKey`**: Most reliable for global hotkeys. Works even when other apps are focused. Only method kept in v1.
- **NSEvent monitors**: Redundant with Carbon, added noise
- **CGEventTap**: Overkill for hotkey (needed separate thread + run loop). Reserved for text selection fallback.

### Text Selection: Three-Stage Approach
1. **AX API** (`AXUIElementCopyAttributeValue`): Works in native macOS apps (TextEdit, Safari, Notes). Fastest — direct read, no clipboard mutation.
2. **CGEvent Cmd+C**: Posts keyboard event from our process. Works in Electron apps (VS Code), Chrome, and apps where AX fails. Must use `CGEventTapLocation.cgAnnotatedSessionEventTap`.
3. **Fail with guidance**: If both fail, tell user to Cmd+C first.

**Critical**: `osascript` subprocess for Cmd+C does NOT work — the subprocess lacks the parent app's Accessibility permission. CGEvent posted from our own process inherits the app's AX grant.

### Accessibility Permissions + Ad-Hoc Signing
- Ad-hoc `codesign -s -` generates a new identity each build
- macOS TCC invalidates Accessibility grants when code signature changes
- **Solution**: `tccutil reset Accessibility <bundle-id>` before each launch in install.sh, so the app re-prompts cleanly
- `AXIsProcessTrustedWithOptions` with prompt flag triggers the system dialog on first launch

### Streaming API
- Anthropic SSE format: `data: {"type": "content_block_delta", "delta": {"text": "..."}}`
- `URLSession.shared.bytes(for:)` for async streaming in Swift
- Level-3-first prompt design: LLM produces Intermediate explanation first (streamed live), then remaining levels silently after `---LEVEL---` delimiter
- Seamless UX: user reads streaming level 3, then arrow keys unlock all 5 levels with no visual jump

### Multi-Monitor
- `NSScreen.main` always returns primary display
- Must use `NSEvent.mouseLocation` + `NSMouseInRect` to find the screen where the cursor is
