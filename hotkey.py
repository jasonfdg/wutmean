import threading
from Quartz import (
    CGEventTapCreate,
    CGEventTapEnable,
    CGEventGetIntegerValueField,
    kCGSessionEventTap,
    kCGHeadInsertEventTap,
    kCGEventKeyDown,
    kCGKeyboardEventKeycode,
)
from CoreFoundation import (
    CFMachPortCreateRunLoopSource,
    CFRunLoopAddSource,
    CFRunLoopGetCurrent,
    CFRunLoopRun,
    kCFRunLoopDefaultMode,
)

# F5 keycode on macOS
F5_KEYCODE = 96


class HotkeyListener:
    def __init__(self, on_f5):
        self._on_f5 = on_f5

    def _callback(self, proxy, event_type, event, refcon):
        keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)
        if keycode == F5_KEYCODE:
            self._on_f5()
        return event

    def start(self):
        """Start listening on a background thread."""
        thread = threading.Thread(target=self._run, daemon=True)
        thread.start()

    def _run(self):
        tap = CGEventTapCreate(
            kCGSessionEventTap,
            kCGHeadInsertEventTap,
            0,  # default tap (not passive)
            1 << kCGEventKeyDown,
            self._callback,
            None,
        )
        if tap is None:
            print("ERROR: Could not create event tap. Check Accessibility permissions.")
            return

        source = CFMachPortCreateRunLoopSource(None, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode)
        CGEventTapEnable(tap, True)
        CFRunLoopRun()
