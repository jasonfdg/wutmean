# wutmean

You're reading something — a paper, a codebase, a contract — and you hit a word you don't know.

What happens next is stupid. You copy the word. You switch to ChatGPT, or Google, or a new tab. You paste it. You wait. You read the answer. You switch back. You find your place again. The context you were building in your head is gone. For one word.

wutmean exists because that friction is insane for 2025. Select the text. Double-tap a key. A popup appears instantly with an explanation — right where you are, no context switch, no tab juggling. Hit Esc and you're back to reading. The whole thing takes two seconds.

Three levels of explanation (Plain → Technical → Examples), arrow keys to switch between them, related terms you can click to go deeper. Works with Anthropic, OpenAI, or Google models. That's it.

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
