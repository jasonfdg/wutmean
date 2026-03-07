from ApplicationServices import (
    AXUIElementCreateSystemWide,
    AXUIElementCopyAttributeValue,
)

kAXFocusedUIElementAttribute = "AXFocusedUIElement"
kAXSelectedTextAttribute = "AXSelectedText"

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
