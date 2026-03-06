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
