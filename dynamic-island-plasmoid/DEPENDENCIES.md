# Dependencies

Built for **KDE Plasma 6** using QML and the Python 3 standard library (no pip packages required).

## Core Requirements
- **KDE Plasma >= 6.0** (`plasmashell`, `kpackagetool6`)
- **Qt 6 Kirigami & Plasma5Support** (`qml6-module-org-kde-kirigami`, `qml6-module-org-kde-plasma-plasma5support`)
- **Python >= 3.8** (Gemini HTTPS requests, `.txt` notes, local audio indexing)
- **xdg-utils & xdg-user-dirs** (`xdg-open`, `xdg-user-dir`)

## Optional (Feature-Specific)
- **Firefox**: Default browser for searches (falls back to `xdg-open`)
- **Rhythmbox**: Local music playback and seek sync (falls back to `xdg-open`)
- **ffprobe (`ffmpeg`)** or **python3-mutagen**: Audio track duration for the progress bar
- **gdbus (`libglib2.0-bin`)**: Syncs seek position with Rhythmbox

## Ubuntu / KDE Neon Install
```bash
sudo apt install plasma-desktop qml6-module-org-kde-kirigami qml6-module-org-kde-plasma-plasma5support python3 xdg-utils xdg-user-dirs rhythmbox ffmpeg libglib2.0-bin
```
