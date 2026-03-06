# Instant Explain Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A Mac background daemon that listens for F5, reads selected text, and shows a floating dark popup with 5 pre-loaded explanation levels (left/right to toggle, Esc to dismiss) — all feeling instantaneous.

**Architecture:** A Python daemon runs silently in the background at all times. At startup it pre-creates a hidden Tkinter window (so there's zero window-creation cost on F5). On F5: selected text is grabbed via macOS Accessibility API, the popup is shown immediately in a "loading" state, and a background thread fires a single Claude API call returning all 5 levels as JSON. Left/right swaps text locally with zero latency.

**Tech Stack:** Python 3.11+, `pynput` (global hotkey), `pyobjc` (Accessibility API for selected text), `anthropic` SDK (claude-haiku-4-5, fastest model), `tkinter` (pre-created hidden overlay window)

**Speed Principles:**
- Popup window pre-created at daemon start → F5 shows it in <10ms
- Selected text read via Accessibility API (no clipboard hijack, no delay)
- Single API call → all 5 levels returned as JSON → left/right is pure local string swap
- Claude Haiku (fastest model, ~500 tokens output)
- Daemon always running → zero startup cost per use

---

### Task 1: Project Setup

**Files:**
- Create: `~/Developer/instant-explain/main.py`
- Create: `~/Developer/instant-explain/requirements.txt`
- Create: `~/Developer/instant-explain/.env.example`

**Step 1: Create the project directory and virtual environment**

```bash
cd ~/Developer/instant-explain
python3 -m venv .venv
source .venv/bin/activate
```

**Step 2: Create `requirements.txt`**

```
anthropic==0.40.0
pynput==1.7.6
pyobjc-framework-Cocoa==10.3.1
pyobjc-framework-Quartz==10.3.1
python-dotenv==1.0.0
```

**Step 3: Install dependencies**

```bash
pip install -r requirements.txt
```

Expected: All packages install without error. `pyobjc` may take 30-60s.

**Step 4: Create `.env.example`**

```bash
ANTHROPIC_API_KEY=your_key_here
```

**Step 5: Copy to `.env` and fill in your key**

```bash
cp .env.example .env
# Edit .env and paste your Anthropic API key
```

**Step 6: Commit**

```bash
git init
echo ".env" >> .gitignore
echo ".venv/" >> .gitignore
git add .
git commit -m "feat: project setup"
```

---

### Task 2: Accessibility Permission Check

macOS requires explicit user permission for apps to read selected text from other apps.

**Files:**
- Create: `~/Developer/instant-explain/permissions.py`

**Step 1: Create `permissions.py`**

```python
import subprocess
import sys

def check_accessibility():
    """Check if this Python process has Accessibility access."""
    from Cocoa import NSWorkspace
    from Quartz import AXIsProcessTrustedWithOptions, kAXTrustedCheckOptionPrompt
    from Foundation import NSDictionary

    options = NSDictionary.dictionaryWithObject_forKey_(
        True, kAXTrustedCheckOptionPrompt
    )
    trusted = AXIsProcessTrustedWithOptions(options)
    if not trusted:
        print("⚠️  Accessibility permission required.")
        print("   System Settings → Privacy & Security → Accessibility")
        print("   Add Terminal (or your terminal app) and enable it.")
        print("   Then restart this script.")
        sys.exit(1)
    print("✓ Accessibility permission granted.")

if __name__ == "__main__":
    check_accessibility()
```

**Step 2: Run it**

```bash
source .venv/bin/activate
python permissions.py
```

Expected: Either a system dialog appears asking for permission, or prints "✓ Accessibility permission granted."

**Step 3: If prompted**, go to System Settings → Privacy & Security → Accessibility → add Terminal → toggle on.

**Step 4: Commit**

```bash
git add permissions.py
git commit -m "feat: accessibility permission checker"
```

---

### Task 3: Selected Text Reader

**Files:**
- Create: `~/Developer/instant-explain/text_reader.py`

**Step 1: Create `text_reader.py`**

```python
from Quartz import (
    AXUIElementCreateSystemWide,
    AXUIElementCopyAttributeValue,
    kAXFocusedUIElementAttribute,
    kAXSelectedTextAttribute,
)

def get_selected_text() -> str:
    """
    Read selected text from focused app via Accessibility API.
    Returns empty string if nothing selected or permission denied.
    Does NOT touch the clipboard.
    """
    try:
        system_element = AXUIElementCreateSystemWide()

        err, focused = AXUIElementCopyAttributeValue(
            system_element, kAXFocusedUIElementAttribute, None
        )
        if err or not focused:
            return ""

        err, selected = AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextAttribute, None
        )
        if err or not selected:
            return ""

        return str(selected).strip()
    except Exception:
        return ""
```

**Step 2: Test it manually**

Open a text file or browser, select some text, then run:

```bash
python -c "from text_reader import get_selected_text; print(repr(get_selected_text()))"
```

Expected: Prints the text you had selected.

**Step 3: Commit**

```bash
git add text_reader.py
git commit -m "feat: selected text reader via Accessibility API"
```

---

### Task 4: Claude API — One-Shot 5 Levels

**Files:**
- Create: `~/Developer/instant-explain/explainer.py`

**Step 1: Create `explainer.py`**

```python
import json
import os
from anthropic import Anthropic

client = Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

PROMPT_TEMPLATE = """Explain the following text at exactly 5 difficulty levels.

Return ONLY valid JSON, no markdown, no explanation outside the JSON:
{{
  "levels": [
    "ELI5 (1-2 sentences, like explaining to a 10-year-old)",
    "Simple (2-3 sentences, plain English for a smart non-expert)",
    "Contextual (2-3 sentences, pitched just at the edge of understanding for someone already reading technical content)",
    "Technical (2-3 sentences, precise terminology, assumes domain knowledge)",
    "Expert (2-3 sentences, assumes deep expertise, include nuance or edge cases)"
  ]
}}

Text to explain:
{text}"""

def fetch_explanations(text: str) -> list[str]:
    """
    Call Claude Haiku once, get all 5 explanation levels.
    Returns list of 5 strings. Raises on API error.
    """
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=600,
        messages=[
            {"role": "user", "content": PROMPT_TEMPLATE.format(text=text)}
        ]
    )
    raw = response.content[0].text.strip()
    data = json.loads(raw)
    return data["levels"]
```

**Step 2: Write a quick smoke test**

```bash
python -c "
from dotenv import load_dotenv; load_dotenv()
from explainer import fetch_explanations
levels = fetch_explanations('proof of work')
for i, l in enumerate(levels): print(f'Level {i}: {l[:80]}')
"
```

Expected: 5 lines printed, each a different complexity explanation of "proof of work". Should complete in 1-3 seconds.

**Step 3: Commit**

```bash
git add explainer.py
git commit -m "feat: one-shot 5-level Claude Haiku explainer"
```

---

### Task 5: Pre-Created Hidden Popup Window

This is the core speed trick: Tkinter window exists at daemon start, we just show/hide it.

**Files:**
- Create: `~/Developer/instant-explain/popup.py`

**Step 1: Create `popup.py`**

```python
import tkinter as tk
from tkinter import font as tkfont
import threading

LEVELS = ["ELI5", "Simple", "Contextual", "Technical", "Expert"]
BG = "#1a1a1a"
FG = "#e8e8e8"
ACCENT = "#4a9eff"
DIM = "#555555"
WIDTH = 520
PADDING = 20

class ExplainPopup:
    def __init__(self):
        self.root = tk.Tk()
        self.root.withdraw()  # Hidden at startup
        self._configure_window()
        self._build_ui()
        self._bind_keys()

        self.levels: list[str] = []
        self.current_level = 2  # Start at "Contextual"
        self.loading = False

    def _configure_window(self):
        r = self.root
        r.overrideredirect(True)       # No title bar, no borders
        r.attributes("-topmost", True) # Always on top
        r.attributes("-alpha", 0.97)   # Slight transparency
        r.configure(bg=BG)
        r.resizable(False, False)

    def _build_ui(self):
        r = self.root

        # Level indicator row
        self.level_label = tk.Label(
            r, text="", bg=BG, fg=ACCENT,
            font=("SF Pro Display", 11, "bold"), anchor="w"
        )
        self.level_label.pack(fill="x", padx=PADDING, pady=(PADDING, 4))

        # Navigation hint
        self.nav_hint = tk.Label(
            r, text="← simpler  ·  harder →  ·  Esc to close",
            bg=BG, fg=DIM, font=("SF Pro Display", 9), anchor="w"
        )
        self.nav_hint.pack(fill="x", padx=PADDING, pady=(0, 10))

        # Separator
        sep = tk.Frame(r, bg="#333333", height=1)
        sep.pack(fill="x", padx=PADDING)

        # Main explanation text
        self.text_label = tk.Label(
            r, text="", bg=BG, fg=FG,
            font=("SF Pro Display", 13),
            wraplength=WIDTH - (PADDING * 2),
            justify="left", anchor="w"
        )
        self.text_label.pack(fill="x", padx=PADDING, pady=PADDING)

        # Follow-up input (hidden until Enter pressed)
        self.input_frame = tk.Frame(r, bg=BG)
        self.input_var = tk.StringVar()
        self.input_box = tk.Entry(
            self.input_frame, textvariable=self.input_var,
            bg="#2a2a2a", fg=FG, insertbackground=FG,
            font=("SF Pro Display", 12), relief="flat",
            highlightthickness=1, highlightcolor=ACCENT,
            width=40
        )
        self.input_box.pack(padx=PADDING, pady=(0, PADDING), fill="x")

    def _bind_keys(self):
        self.root.bind("<Escape>", lambda e: self.hide())
        self.root.bind("<Left>", lambda e: self._navigate(-1))
        self.root.bind("<Right>", lambda e: self._navigate(1))
        self.root.bind("<Return>", lambda e: self._show_input())
        self.input_box.bind("<Return>", self._submit_followup)
        self.input_box.bind("<Escape>", lambda e: self._hide_input())

    def show_loading(self, x: int, y: int):
        """Show immediately with loading state — called from hotkey thread."""
        self.levels = []
        self.current_level = 2
        self.level_label.config(text="Explaining...")
        self.text_label.config(text="")
        self._hide_input()
        self._position(x, y)
        self.root.deiconify()
        self.root.focus_force()
        self.loading = True

    def show_levels(self, levels: list[str]):
        """Populate with fetched levels — called from background thread via after()."""
        self.levels = levels
        self.loading = False
        self._render()

    def _render(self):
        if not self.levels:
            return
        idx = self.current_level
        self.level_label.config(text=f"[ {LEVELS[idx]} ]  {idx + 1}/5")
        self.text_label.config(text=self.levels[idx])
        # Resize window to fit content
        self.root.update_idletasks()

    def _navigate(self, direction: int):
        if not self.levels:
            return
        self.current_level = max(0, min(4, self.current_level + direction))
        self._render()

    def _position(self, x: int, y: int):
        self.root.update_idletasks()
        w = WIDTH + (PADDING * 2)
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        # Keep popup on screen
        px = min(x, screen_w - w - 20)
        py = min(y + 24, screen_h - 200)
        self.root.geometry(f"+{px}+{py}")

    def _show_input(self):
        if not self.input_frame.winfo_ismapped():
            self.input_frame.pack(fill="x")
            self.input_box.focus_set()

    def _hide_input(self):
        self.input_frame.pack_forget()
        self.input_var.set("")
        self.root.focus_force()

    def _submit_followup(self, event):
        question = self.input_var.get().strip()
        if not question:
            return
        self._hide_input()
        self.level_label.config(text="Thinking...")
        self.text_label.config(text="")
        # Trigger new fetch in background
        if self._on_followup:
            threading.Thread(
                target=self._on_followup, args=(question,), daemon=True
            ).start()

    def hide(self):
        self.root.withdraw()

    def run(self, on_followup=None):
        self._on_followup = on_followup
        self.root.mainloop()
```

**Step 2: Smoke test the popup in isolation**

```bash
python -c "
from popup import ExplainPopup
import threading, time

p = ExplainPopup()

def demo():
    time.sleep(0.5)
    p.show_loading(400, 400)
    time.sleep(1)
    p.root.after(0, p.show_levels, [
        'Proof of work is like solving a really hard puzzle.',
        'Computers race to solve a math puzzle; the winner adds the next block.',
        'Miners hash block headers with a nonce until output meets a difficulty target.',
        'SHA-256 iterated over block header; valid if hash < target derived from difficulty bits.',
        'Nakamoto consensus via hashcash PoW — difficulty adjusts every 2016 blocks to target 10min intervals.'
    ])

threading.Thread(target=demo, daemon=True).start()
p.run()
"
```

Expected: Dark floating popup appears at center, shows "Explaining..." then fills with text. Left/right arrows cycle levels. Esc closes.

**Step 3: Commit**

```bash
git add popup.py
git commit -m "feat: pre-created hidden popup window with level navigation"
```

---

### Task 6: Global Hotkey Daemon (F5)

**Files:**
- Create: `~/Developer/instant-explain/hotkey.py`

**Step 1: Create `hotkey.py`**

```python
from pynput import keyboard

F5 = keyboard.Key.f5

class HotkeyListener:
    def __init__(self, on_f5):
        self._on_f5 = on_f5
        self._listener = keyboard.Listener(on_press=self._on_press)

    def _on_press(self, key):
        if key == F5:
            self._on_f5()

    def start(self):
        self._listener.start()

    def stop(self):
        self._listener.stop()
```

**Step 2: Test it**

```bash
python -c "
from hotkey import HotkeyListener
import time

def on_f5():
    print('F5 pressed!')

h = HotkeyListener(on_f5)
h.start()
print('Press F5...')
time.sleep(10)
"
```

Expected: "F5 pressed!" prints each time you press F5.

**Step 3: Commit**

```bash
git add hotkey.py
git commit -m "feat: global F5 hotkey listener"
```

---

### Task 7: Mouse Position Helper

We need cursor position to place the popup near the selection.

**Files:**
- Create: `~/Developer/instant-explain/cursor_pos.py`

**Step 1: Create `cursor_pos.py`**

```python
from Quartz import CGEventCreate, CGEventGetLocation, kCGEventNull

def get_cursor_position() -> tuple[int, int]:
    """Returns current mouse cursor (x, y) in screen coordinates."""
    event = CGEventCreate(None)
    loc = CGEventGetLocation(event)
    return int(loc.x), int(loc.y)
```

**Step 2: Test it**

```bash
python -c "
from cursor_pos import get_cursor_position
print(get_cursor_position())
"
```

Expected: Prints something like `(842, 531)`.

**Step 3: Commit**

```bash
git add cursor_pos.py
git commit -m "feat: cursor position helper"
```

---

### Task 8: Wire Everything Together in `main.py`

**Files:**
- Create: `~/Developer/instant-explain/main.py`

**Step 1: Create `main.py`**

```python
import os
import threading
from dotenv import load_dotenv

load_dotenv()

from permissions import check_accessibility
from text_reader import get_selected_text
from cursor_pos import get_cursor_position
from explainer import fetch_explanations
from popup import ExplainPopup
from hotkey import HotkeyListener

popup = ExplainPopup()

def on_f5():
    text = get_selected_text()
    if not text:
        return  # Nothing selected, do nothing

    x, y = get_cursor_position()

    # Show loading state IMMEDIATELY (< 10ms)
    popup.root.after(0, popup.show_loading, x, y)

    # Fetch in background thread
    def fetch():
        try:
            levels = fetch_explanations(text)
        except Exception as e:
            levels = [f"Error: {e}"] * 5
        # Update UI on main thread
        popup.root.after(0, popup.show_levels, levels)

    threading.Thread(target=fetch, daemon=True).start()

def on_followup(question: str):
    """Called when user submits a follow-up question."""
    def fetch():
        try:
            levels = fetch_explanations(question)
        except Exception as e:
            levels = [f"Error: {e}"] * 5
        popup.root.after(0, popup.show_levels, levels)

    threading.Thread(target=fetch, daemon=True).start()

def main():
    check_accessibility()
    print("✓ Instant Explain running. Select text and press F5.")

    hotkey = HotkeyListener(on_f5)
    hotkey.start()

    popup.run(on_followup=on_followup)  # Blocks — runs Tkinter mainloop

if __name__ == "__main__":
    main()
```

**Step 2: Run the full daemon**

```bash
source .venv/bin/activate
python main.py
```

Expected: Prints "✓ Instant Explain running." — then sits silently.

**Step 3: Test end-to-end**

1. Select any text on screen (in Terminal, browser, anywhere)
2. Press F5
3. Popup appears immediately with "Explaining..."
4. Within 2-3 seconds, text populates
5. Press Left/Right to cycle levels
6. Press Esc to dismiss

**Step 4: Commit**

```bash
git add main.py
git commit -m "feat: wire hotkey + text reader + explainer + popup into daemon"
```

---

### Task 9: Auto-Start on Login (Optional but Recommended)

So you never have to manually start the daemon.

**Files:**
- Create: `~/Library/LaunchAgents/com.instantexplain.daemon.plist`

**Step 1: Find your Python path**

```bash
which python  # while .venv is active
# Should print something like /Users/chaukam/Developer/instant-explain/.venv/bin/python
```

**Step 2: Create the LaunchAgent plist**

Replace `/Users/chaukam/Developer/instant-explain` with actual path if different:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.instantexplain.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/chaukam/Developer/instant-explain/.venv/bin/python</string>
        <string>/Users/chaukam/Developer/instant-explain/main.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/instant-explain.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/instant-explain-error.log</string>
</dict>
</plist>
```

**Step 3: Load it**

```bash
launchctl load ~/Library/LaunchAgents/com.instantexplain.daemon.plist
```

**Step 4: Verify it's running**

```bash
launchctl list | grep instantexplain
```

Expected: Shows the agent with a PID (non-zero means running).

**Step 5: Commit**

```bash
git add .
git commit -m "feat: launchagent for auto-start on login"
```

---

## Verification Checklist

Before calling this done, confirm all of these:

- [ ] F5 press → popup visible in **< 100ms** (feels instant)
- [ ] LLM response arrives in **< 3 seconds** (Haiku is fast)
- [ ] Left/Right switches levels with **zero loading** (pure local swap)
- [ ] Esc dismisses cleanly, no residue on screen
- [ ] Works when text is selected in Terminal, browser, any app
- [ ] Nothing selected → F5 does nothing (no ghost popup)
- [ ] Follow-up Enter → new 5 levels load, same popup
- [ ] Daemon uses < 30MB RAM at idle
- [ ] Auto-starts on login (LaunchAgent)
