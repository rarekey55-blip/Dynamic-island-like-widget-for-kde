# Dynamic Island for KDE Plasma 6

Morphing glassmorphic Dynamic Island plasmoid for **KDE Plasma 6** featuring a multi-engine web launcher, inline Gemini AI assistant, quick `.txt` note pad, and zero-idle-CPU local music player with a capsule progress bar.

## Installation
1. Install dependencies from [DEPENDENCIES.md](DEPENDENCIES.md).
2. Install the plasmoid:
```bash
kpackagetool6 --type Plasma/Applet --install com.custom.dynamicislandsearch
```
3. Right-click desktop or panel -> **Add Widgets...** -> search **Dynamic Island**.

## Gemini API Key
Edit `com.custom.dynamicislandsearch/contents/ui/main.qml` and replace `YOUR_GEMINI_API_KEY` in:
```qml
property string geminiApiKey: "YOUR_GEMINI_API_KEY"
```
Then reload Plasma:
```bash
systemctl --user restart plasma-plasmashell.service
```

## Shortcuts & Bangs
- `Tab`: Cycle tabs | `Enter`: Submit / Play top song | `Ctrl+Enter`: Save note | `Esc`: Collapse
- `!g`, `!yt`, `!gh`, `!ddg`: Search Google, YouTube, GitHub, DuckDuckGo
- `!ai <prompt>`: Ask Gemini inline | `!note <text>`: Quick-save note to `~/notes`
