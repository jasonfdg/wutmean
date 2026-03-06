from Quartz import CGEventCreate, CGEventGetLocation

def get_cursor_position() -> tuple[int, int]:
    """Returns current mouse cursor (x, y) in screen coordinates."""
    event = CGEventCreate(None)
    loc = CGEventGetLocation(event)
    return int(loc.x), int(loc.y)
