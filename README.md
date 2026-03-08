# wutmean

You're deep in a paper, a codebase, a contract — and you hit a word you don't know.

So you copy it. Cmd+Tab to a browser. Open ChatGPT or Google. Paste. Wait. Read. Cmd+Tab back. Find where you were. The thread you were holding in your head? Gone. For one word.

Or you're in a terminal — Claude Code, a shell, whatever — and you see something you want to look up. Now you're either scrolling to the bottom to ask a throwaway question and losing your place, or you're opening a whole new window just to get a one-line answer. Either way you've broken your flow for something that should take two seconds.

wutmean makes it take two seconds. Select text. Double-tap F1. A popup shows up right there with an explanation. Esc to close. You never leave what you're doing.

Three levels (Plain → Technical → Examples), arrow keys to switch, related terms you can click to keep going. Anthropic, OpenAI, or Google — bring your own key. That's the whole thing.

<!-- Replace with your actual demo GIF -->
![demo](https://github.com/user-attachments/assets/PLACEHOLDER-REPLACE-WITH-ACTUAL-GIF)

## Install

### Homebrew (recommended)

```
brew install --cask wutmean
```

### Manual

```sh
curl -sL https://github.com/jasonfdg/wutmean/releases/latest/download/wutmean.zip -o /tmp/wutmean.zip
unzip -o /tmp/wutmean.zip -d /Applications
open /Applications/wutmean.app
```

### Build from source

```sh
git clone https://github.com/jasonfdg/wutmean.git
cd wutmean
./install.sh
```

Requires Swift 5.9+ and macOS 13+.

## Setup

1. Launch wutmean — it appears as **wut** in your menu bar
2. Click **wut → Settings** and paste your API key(s)
   - Anthropic (`sk-ant-...`), OpenAI (`sk-...`), or Google (`AIza...`)
   - One key per line — use models from any provider
3. Select the model you want from the dropdown
4. Grant **Accessibility** when prompted (System Settings → Privacy & Security → Accessibility)

## Usage

| Action | What happens |
|--------|-------------|
| Select text + **double-tap F1** | Explanation popup appears |
| **← / →** arrow keys | Switch between Plain / Technical / Examples |
| Click a related term | Explain that term in the same popup |
| **Esc** | Dismiss |
| **⎘** | Copy current explanation |
| **⋯** | Search Google or YouTube |

The hotkey is configurable in Settings.

## Three levels

**Plain** — No jargon. 2-3 sentences. A memorable anchor.

**Technical** — Correct terminology, key distinctions, one common misconception addressed.

**Examples** — Three examples that reveal meaning through use: one correct, one near-miss, one in context.

## Config

Config lives at `~/.config/wutmean/config.json`. The prompt template is at `~/.config/wutmean/prompt.md` — edit it from the menu bar (Edit Prompt).

## Requirements

- macOS 13 (Ventura) or later
- An API key from Anthropic, OpenAI, or Google

## License

MIT
