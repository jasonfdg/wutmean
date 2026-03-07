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
    # Toggle: if popup is visible, hide it
    if popup.is_visible:
        popup.root.after(0, popup.hide)
        return

    text = get_selected_text()
    if not text:
        return

    x, y = get_cursor_position()

    # Show loading state IMMEDIATELY (< 10ms)
    popup.root.after(0, popup.show_loading, x, y)

    # Fetch in background thread
    def fetch():
        try:
            levels = fetch_explanations(text)
        except Exception as e:
            levels = [f"Error: {e}"] * 5
        popup.root.after(0, popup.show_levels, levels)

    threading.Thread(target=fetch, daemon=True).start()


def on_followup(question: str):
    """Called when user submits a follow-up question."""
    try:
        levels = fetch_explanations(question)
    except Exception as e:
        levels = [f"Error: {e}"] * 5
    popup.root.after(0, popup.show_levels, levels)


def main():
    check_accessibility()
    print("Instant Explain running. Select text and press F5.")

    hotkey = HotkeyListener(on_f5)
    hotkey.start()

    popup.run(on_followup=on_followup)  # Blocks — runs Tkinter mainloop


if __name__ == "__main__":
    main()
