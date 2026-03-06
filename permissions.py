import sys

def check_accessibility():
    """Check if this Python process has Accessibility access."""
    from Quartz import AXIsProcessTrustedWithOptions
    from Foundation import NSDictionary

    options = NSDictionary.dictionaryWithObject_forKey_(
        True, "AXTrustedCheckOptionPrompt"
    )
    trusted = AXIsProcessTrustedWithOptions(options)
    if not trusted:
        print("Accessibility permission required.")
        print("   System Settings -> Privacy & Security -> Accessibility")
        print("   Add Terminal (or your terminal app) and enable it.")
        print("   Then restart this script.")
        sys.exit(1)
    print("Accessibility permission granted.")

if __name__ == "__main__":
    check_accessibility()
