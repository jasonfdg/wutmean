import tkinter as tk
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
        self._on_followup = None
        self._drag_x = 0
        self._drag_y = 0

    def _configure_window(self):
        r = self.root
        r.overrideredirect(True)       # No title bar, no borders
        r.attributes("-topmost", True) # Always on top
        r.attributes("-alpha", 0.97)   # Slight transparency
        r.configure(bg=BG)
        r.resizable(False, False)

    def _build_ui(self):
        r = self.root

        # Top bar: draggable + close button
        top_bar = tk.Frame(r, bg=BG)
        top_bar.pack(fill="x", padx=PADDING, pady=(PADDING, 0))

        # Level indicator (left side, draggable)
        self.level_label = tk.Label(
            top_bar, text="", bg=BG, fg=ACCENT,
            font=("SF Pro Display", 11, "bold"), anchor="w"
        )
        self.level_label.pack(side="left", fill="x", expand=True)

        # Close button (right side)
        close_btn = tk.Label(
            top_bar, text="  x  ", bg=BG, fg=DIM,
            font=("SF Pro Display", 11), cursor="hand2"
        )
        close_btn.pack(side="right")
        close_btn.bind("<Button-1>", lambda e: self.hide())
        close_btn.bind("<Enter>", lambda e: close_btn.config(fg=FG))
        close_btn.bind("<Leave>", lambda e: close_btn.config(fg=DIM))

        # Make top bar draggable
        for widget in (top_bar, self.level_label):
            widget.bind("<Button-1>", self._start_drag)
            widget.bind("<B1-Motion>", self._do_drag)

        # Navigation hint
        self.nav_hint = tk.Label(
            r, text="<- simpler  |  harder ->  |  Esc close  |  Enter follow-up",
            bg=BG, fg=DIM, font=("SF Pro Display", 9), anchor="w"
        )
        self.nav_hint.pack(fill="x", padx=PADDING, pady=(4, 10))

        # Separator
        sep = tk.Frame(r, bg="#333333", height=1)
        sep.pack(fill="x", padx=PADDING)

        # Main explanation text
        self.text_label = tk.Label(
            r, text="", bg=BG, fg=FG,
            font=("SF Pro Display", 13),
            wraplength=WIDTH - (PADDING * 2),
            justify="left", anchor="nw"
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
        """Show immediately with loading state."""
        self.levels = []
        self.current_level = 2
        self.loading = True
        self.level_label.config(text="Explaining...")
        self.text_label.config(text="")
        self._hide_input()
        self._position(x, y)
        self.root.deiconify()
        self.root.focus_force()

    def show_levels(self, levels: list[str]):
        """Populate with fetched levels."""
        self.levels = levels
        self.loading = False
        self._render()

    def _render(self):
        if not self.levels:
            return
        idx = self.current_level
        self.level_label.config(text=f"[ {LEVELS[idx]} ]  {idx + 1}/5")
        self.text_label.config(text=self.levels[idx])
        self.root.update_idletasks()

    def _start_drag(self, event):
        self._drag_x = event.x_root - self.root.winfo_x()
        self._drag_y = event.y_root - self.root.winfo_y()

    def _do_drag(self, event):
        x = event.x_root - self._drag_x
        y = event.y_root - self._drag_y
        self.root.geometry(f"+{x}+{y}")

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
        px = min(x, screen_w - w - 20)
        py = min(y + 24, screen_h - 200)
        self.root.geometry(f"+{px}+{py}")

    def _show_input(self):
        if self.loading:
            return
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
        self.loading = True
        if self._on_followup:
            threading.Thread(
                target=self._on_followup, args=(question,), daemon=True
            ).start()

    @property
    def is_visible(self):
        return self.root.state() != "withdrawn"

    def hide(self):
        self.root.withdraw()

    def run(self, on_followup=None):
        self._on_followup = on_followup
        self.root.mainloop()
