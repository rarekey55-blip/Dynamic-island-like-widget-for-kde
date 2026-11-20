import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.status: root.isOpen ? PlasmaCore.Types.AcceptingInputStatus : PlasmaCore.Types.PassiveStatus
    preferredRepresentation: fullRepresentation

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 4
    Layout.preferredWidth: Kirigami.Units.gridUnit * 35
    Layout.preferredHeight: Kirigami.Units.gridUnit * 20

    // Gemini configuration
    property string geminiApiKey: "YOUR_GEMINI_API_KEY"
    readonly property string preferredGeminiModel: "gemini-3.5-flash-lite"
    property string activeModelUsed: "gemini-3.5-flash-lite"

    property bool isOpen: false
    property bool pinnedOpen: false
    property bool inputActive: false
    property string liveActivityText: ""
    property color liveActivityColor: "#34D399"
    property int currentEngineIndex: 0

    // Inline Gemini drawer state
    property bool isGeminiLoading: false
    property string geminiResponseText: ""
    property string geminiErrorText: ""
    property string lastGeminiPrompt: ""

    // Note drawer state
    property string noteStatusText: ""
    property bool noteStatusError: false
    property string activeNotesDir: "~/notes"

    // Local Music Library & Progress state (0% idle CPU when paused/stopped)
    property bool isLocalMusicSearching: false
    property bool localMusicLoadedOnce: false
    property int musicSearchSeq: 0
    property var localMusicResults: []
    property int currentLocalTrackIndex: -1
    property string currentLocalTrackName: "Select a local track"
    property string currentLocalTrackFolder: "Indexes ~/Music, ~/Downloads & ~/Desktop"
    property string currentLocalTrackPath: ""
    property string currentLocalTrackUri: ""
    property bool localMusicPlaying: false
    property real localTrackElapsedSec: 0
    property real localTrackDurationSec: 0
    property int playbackSyncTicks: 0

    // Desaturated, editorial accent palette
    readonly property var engines: [
        { name: "Google",     short: "Google",  bang: "!g",    color: "#60A5FA", url: "https://www.google.com/search?q=" },
        { name: "YouTube",    short: "YouTube", bang: "!yt",   color: "#F87171", url: "https://www.youtube.com/results?search_query=" },
        { name: "GitHub",     short: "GitHub",  bang: "!gh",   color: "#C084FC", url: "https://github.com/search?q=" },
        { name: "DuckDuckGo", short: "DDG",     bang: "!ddg",  color: "#FB923C", url: "https://duckduckgo.com/?q=" },
        { name: "Gemini",     short: "Gemini",  bang: "!ai",   color: "#38BDF8", url: "" },
        { name: "Note",       short: "Note",    bang: "!note", color: "#34D399", url: "" },
        { name: "Music",      short: "Music",   bang: "",      color: "#F472B6", url: "" }
    ]

    readonly property color activeAccent: engines[currentEngineIndex].color

    signal shortcutTriggered()

    Connections {
        target: Plasmoid
        function onActivated() {
            root.shortcutTriggered()
        }
    }

    // Firefox / Folder / Track launcher DataSource
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    // Dedicated Gemini API DataSource
    Plasma5Support.DataSource {
        id: geminiExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var out = data["stdout"] || ""
            var err = data["stderr"] || ""
            disconnectSource(sourceName)
            root.handleGeminiResult(out, err)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    // Dedicated Note Writer DataSource
    Plasma5Support.DataSource {
        id: noteExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var out = data["stdout"] || ""
            var err = data["stderr"] || ""
            disconnectSource(sourceName)
            root.handleNoteResult(out, err)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    // Dedicated Local Music Indexer DataSource
    Plasma5Support.DataSource {
        id: localMusicExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var out = data["stdout"] || ""
            disconnectSource(sourceName)
            root.handleLocalMusicResult(out)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    // Dedicated Track Duration & Rhythmbox Position Sync DataSource
    Plasma5Support.DataSource {
        id: trackMetaExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var out = data["stdout"] || ""
            disconnectSource(sourceName)
            root.handleTrackMetaResult(out)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    Timer {
        id: activityResetTimer
        interval: 2400
        repeat: false
        onTriggered: root.liveActivityText = ""
    }

    Timer {
        id: noteStatusResetTimer
        interval: 3200
        repeat: false
        onTriggered: {
            root.noteStatusText = ""
            root.noteStatusError = false
        }
    }

    // Runs ONLY while a local track is actively playing (0% CPU when paused/stopped)
    Timer {
        id: localPlaybackTimer
        interval: 500
        repeat: true
        running: root.localMusicPlaying && root.currentLocalTrackPath.length > 0
        onTriggered: {
            root.localTrackElapsedSec += 0.5
            root.playbackSyncTicks += 1

            if (root.localTrackDurationSec > 0 && root.localTrackElapsedSec >= root.localTrackDurationSec) {
                if (root.localMusicResults.length > 1) {
                    root.playNextLocalTrack()
                } else {
                    root.localTrackElapsedSec = 0
                    root.localMusicPlaying = false
                }
                return
            }

            // Every 4 seconds during active playback, sync exact position with Rhythmbox via lightweight gdbus
            if (root.playbackSyncTicks >= 8) {
                root.playbackSyncTicks = 0
                root.syncActiveRhythmboxPosition()
            }
        }
    }

    function formatSeconds(sec) {
        var s = Math.max(0, Math.floor(sec || 0))
        var mins = Math.floor(s / 60)
        var rem = s % 60
        return mins + ":" + (rem < 10 ? "0" + rem : rem)
    }

    function cycleEngine() {
        root.currentEngineIndex = (root.currentEngineIndex + 1) % root.engines.length
        if (root.engines[root.currentEngineIndex].name === "Music" && !root.localMusicLoadedOnce) {
            root.searchLocalMusic("")
        }
        focusDelayTimer.restart()
    }

    function looksLikeUrl(text) {
        if (!text) return false
        var t = text.trim()
        return /^https?:\/\//i.test(t) || (/^[^\s]+\.[^\s]{2,}$/.test(t) && t.indexOf(" ") === -1)
    }

    function triggerLiveActivity(label, accentColor) {
        root.liveActivityText = label
        root.liveActivityColor = accentColor
        activityResetTimer.restart()
    }

    function clearGeminiDrawer() {
        root.isGeminiLoading = false
        root.geminiResponseText = ""
        root.geminiErrorText = ""
        root.lastGeminiPrompt = ""
    }

    function stringToHex(str) {
        var hex = ""
        for (var i = 0; i < str.length; i++) {
            var code = str.charCodeAt(i)
            hex += ("0000" + code.toString(16)).slice(-4)
        }
        return hex
    }

    // =========================================================
    // NOTE SAVING ENGINE (/notes if writable, else ~/notes)
    // =========================================================
    function handleNoteResult(stdout, stderr) {
        var raw = stdout.trim()
        if (raw.length > 0) {
            try {
                var res = JSON.parse(raw)
                if (res.ok) {
                    root.activeNotesDir = res.dir || "~/notes"
                    root.noteStatusError = false
                    root.noteStatusText = "Saved · " + res.filename
                    noteStatusResetTimer.restart()
                    triggerLiveActivity("Saved " + res.filename, "#34D399")
                    return
                } else {
                    root.noteStatusError = true
                    root.noteStatusText = res.error || "Failed to save note"
                    noteStatusResetTimer.restart()
                    return
                }
            } catch (e) {}
        }
        root.noteStatusError = true
        root.noteStatusText = stderr.trim().length > 0 ? stderr.trim().substring(0, 80) : "Write failed"
        noteStatusResetTimer.restart()
    }

    function saveNote(contentText, customTitle) {
        if (!contentText || contentText.trim().length === 0) return

        var hexBody = stringToHex(contentText)
        var hexTitle = stringToHex(customTitle ? customTitle.trim() : "")

        var pyScript = [
            "import sys, os, json, re, datetime",
            "body = bytes.fromhex(sys.argv[1]).decode('utf-16-be')",
            "title = bytes.fromhex(sys.argv[2]).decode('utf-16-be').strip()",
            "if os.path.isdir('/notes') and os.access('/notes', os.W_OK):",
            "    target_dir = '/notes'",
            "    display_dir = '/notes'",
            "else:",
            "    target_dir = os.path.expanduser('~/notes')",
            "    os.makedirs(target_dir, exist_ok=True)",
            "    display_dir = '~/notes'",
            "if title:",
            "    clean = re.sub(r'[^a-zA-Z0-9._ -]', '_', title).strip()",
            "    if not clean:",
            "        clean = datetime.datetime.now().strftime('note_%Y-%m-%d_%H-%M-%S')",
            "    if not clean.lower().endswith('.txt'):",
            "        clean += '.txt'",
            "    fname = clean",
            "else:",
            "    fname = datetime.datetime.now().strftime('note_%Y-%m-%d_%H-%M-%S.txt')",
            "full_path = os.path.join(target_dir, fname)",
            "try:",
            "    with open(full_path, 'w', encoding='utf-8') as f:",
            "        f.write(body.rstrip() + '\\n')",
            "    print(json.dumps({'ok': True, 'filename': fname, 'dir': display_dir, 'path': full_path}))",
            "except Exception as e:",
            "    print(json.dumps({'ok': False, 'error': str(e)}))"
        ].join("\n")

        var safePy = pyScript.replace(/'/g, "'\\''")
        noteExecutable.exec("python3 -c '" + safePy + "' '" + hexBody + "' '" + hexTitle + "'")
    }

    function openNotesFolder() {
        var cmd = "if [ -d /notes ] && [ -w /notes ]; then nohup xdg-open /notes >/dev/null 2>&1 & " +
                  "else mkdir -p \"$HOME/notes\" && nohup xdg-open \"$HOME/notes\" >/dev/null 2>&1 & fi"
        executable.exec(cmd)
    }

    // =========================================================
    // LOCAL MUSIC LIBRARY, DURATION PROBE & PLAYBACK ENGINE
    // =========================================================
    function handleLocalMusicResult(stdout) {
        root.isLocalMusicSearching = false
        root.localMusicLoadedOnce = true
        var raw = stdout.trim()
        if (raw.length === 0) {
            root.localMusicResults = []
            return
        }
        try {
            var parsed = JSON.parse(raw)
            if (Array.isArray(parsed)) {
                root.localMusicResults = parsed
            }
        } catch (e) {
            root.localMusicResults = []
        }
    }

    function handleTrackMetaResult(stdout) {
        var raw = stdout.trim()
        if (raw.length === 0) return
        try {
            var res = JSON.parse(raw)
            if (res.duration !== undefined && res.duration > 0) {
                root.localTrackDurationSec = res.duration
            }
            if (res.position !== undefined && res.position >= 0) {
                root.localTrackElapsedSec = res.position
            }
            if (res.playing !== undefined) {
                root.localMusicPlaying = !!res.playing
            }
            if (res.trackId && res.trackId.length > 0) {
                root.currentLocalTrackUri = res.trackId
            }
        } catch (e) {}
    }

    function probeLocalTrackDuration(filePath) {
        var safePath = filePath.replace(/'/g, "'\\''")
        var pyDur = [
            "import sys, os, json, subprocess, shutil, wave, contextlib",
            "p = sys.argv[1]",
            "dur = 0.0",
            "if shutil.which('ffprobe'):",
            "    try:",
            "        out = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', p], text=True, timeout=2).strip()",
            "        dur = float(out)",
            "    except Exception:",
            "        pass",
            "if dur <= 0:",
            "    try:",
            "        import mutagen",
            "        mf = mutagen.File(p)",
            "        if mf and mf.info and mf.info.length > 0:",
            "            dur = float(mf.info.length)",
            "    except Exception:",
            "        pass",
            "if dur <= 0 and p.lower().endswith('.wav'):",
            "    try:",
            "        with contextlib.closing(wave.open(p, 'r')) as wf:",
            "            dur = wf.getnframes() / float(wf.getframerate())",
            "    except Exception:",
            "        pass",
            "print(json.dumps({'duration': round(dur, 2)}))"
        ].join("\n")
        var safePy = pyDur.replace(/'/g, "'\\''")
        trackMetaExecutable.exec("python3 -c '" + safePy + "' '" + safePath + "'")
    }

    function syncActiveRhythmboxPosition() {
        var cmd = "python3 -c \"" +
                  "import subprocess, re, json; " +
                  "st = subprocess.check_output(['gdbus', 'call', '--session', '--dest', 'org.mpris.MediaPlayer2.rhythmbox', '--object-path', '/org/mpris/MediaPlayer2', '--method', 'org.freedesktop.DBus.Properties.Get', 'org.mpris.MediaPlayer2.Player', 'PlaybackStatus'], text=True, timeout=1); " +
                  "pos = subprocess.check_output(['gdbus', 'call', '--session', '--dest', 'org.mpris.MediaPlayer2.rhythmbox', '--object-path', '/org/mpris/MediaPlayer2', '--method', 'org.freedesktop.DBus.Properties.Get', 'org.mpris.MediaPlayer2.Player', 'Position'], text=True, timeout=1); " +
                  "meta = subprocess.check_output(['gdbus', 'call', '--session', '--dest', 'org.mpris.MediaPlayer2.rhythmbox', '--object-path', '/org/mpris/MediaPlayer2', '--method', 'org.freedesktop.DBus.Properties.Get', 'org.mpris.MediaPlayer2.Player', 'Metadata'], text=True, timeout=1); " +
                  "pm = re.search(r'(\\d+)', pos); " +
                  "lm = re.search(r\"'mpris:length':\\s*<(?:uint64|int64)?\\s*(\\d+)>\", meta); " +
                  "tm = re.search(r\"'mpris:trackid':\\s*<objectpath\\s*'([^']+)'|'mpris:trackid':\\s*<'([^']+)'>\", meta); " +
                  "tid = (tm.group(1) or tm.group(2)) if tm else ''; " +
                  "print(json.dumps({'playing': 'Playing' in st, 'position': round(int(pm.group(1))/1e6, 2) if pm else -1, 'duration': round(int(lm.group(1))/1e6, 2) if lm else 0, 'trackId': tid}))" +
                  "\" 2>/dev/null"
        trackMetaExecutable.exec(cmd)
    }

    function seekLocalTrack(ratio) {
        if (root.localTrackDurationSec <= 0) return
        var clamped = Math.max(0, Math.min(1, ratio))
        var targetSec = clamped * root.localTrackDurationSec
        root.localTrackElapsedSec = targetSec
        root.playbackSyncTicks = 0

        if (root.currentLocalTrackUri.length > 0) {
            var micros = Math.floor(targetSec * 1000000)
            var safeUri = root.currentLocalTrackUri.replace(/'/g, "'\\''")
            var cmd = "gdbus call --session --dest org.mpris.MediaPlayer2.rhythmbox --object-path /org/mpris/MediaPlayer2 " +
                      "--method org.mpris.MediaPlayer2.Player.SetPosition '" + safeUri + "' " + micros + " >/dev/null 2>&1 &"
            executable.exec(cmd)
        }
    }

    function searchLocalMusic(queryText) {
        root.isLocalMusicSearching = true
        root.musicSearchSeq = (root.musicSearchSeq + 1) % 1000000
        var hexQuery = stringToHex(queryText ? queryText.trim() : "")

        var pyScript = [
            "import sys, os, json, subprocess",
            "q = bytes.fromhex(sys.argv[1]).decode('utf-16-be').strip().lower()",
            "tokens = [t for t in q.split() if t]",
            "exts = ('.mp3', '.flac', '.m4a', '.ogg', '.opus', '.wav', '.aac', '.wma')",
            "roots = []",
            "try:",
            "    xdg_m = subprocess.check_output(['xdg-user-dir', 'MUSIC'], text=True, timeout=1).strip()",
            "    if xdg_m and os.path.isdir(xdg_m):",
            "        roots.append(os.path.realpath(xdg_m))",
            "except Exception:",
            "    pass",
            "for cand in ['~/Music', '~/Downloads', '~/Desktop', '/music']:",
            "    p = os.path.realpath(os.path.expanduser(cand))",
            "    if os.path.isdir(p) and p not in roots:",
            "        roots.append(p)",
            "matches = []",
            "seen = set()",
            "for r in roots:",
            "    for dirpath, dirnames, filenames in os.walk(r):",
            "        dirnames[:] = [d for d in dirnames if not d.startswith('.')]",
            "        for fn in filenames:",
            "            if not fn.lower().endswith(exts):",
            "                continue",
            "            full = os.path.join(dirpath, fn)",
            "            if full in seen:",
            "                continue",
            "            seen.add(full)",
            "            stem = os.path.splitext(fn)[0]",
            "            folder = os.path.basename(dirpath)",
            "            hay = (stem + ' ' + folder).lower()",
            "            if tokens and not all(tok in hay for tok in tokens):",
            "                continue",
            "            try:",
            "                mtime = os.path.getmtime(full)",
            "            except Exception:",
            "                mtime = 0",
            "            starts = 1 if (q and stem.lower().startswith(q)) else 0",
            "            matches.append((starts, mtime, {'name': stem, 'folder': folder, 'path': full}))",
            "matches.sort(key=lambda item: (item[0], item[1]), reverse=True)",
            "print(json.dumps([m[2] for m in matches[:30]]))"
        ].join("\n")

        var safePy = pyScript.replace(/'/g, "'\\''")
        localMusicExecutable.exec("python3 -c '" + safePy + "' '" + hexQuery + "' " + root.musicSearchSeq)
    }

    function playLocalTrackAtIndex(idx) {
        if (idx < 0 || idx >= root.localMusicResults.length) return
        var item = root.localMusicResults[idx]
        root.currentLocalTrackIndex = idx
        root.currentLocalTrackName = item.name
        root.currentLocalTrackFolder = item.folder
        root.currentLocalTrackPath = item.path
        root.currentLocalTrackUri = ""
        root.localTrackElapsedSec = 0
        root.localTrackDurationSec = 0
        root.playbackSyncTicks = 4
        root.localMusicPlaying = true

        probeLocalTrackDuration(item.path)

        var safePath = item.path.replace(/'/g, "'\\''")
        var pyPlay = [
            "import sys, os, urllib.parse, subprocess, shutil",
            "p = sys.argv[1]",
            "uri = 'file://' + urllib.parse.quote(os.path.abspath(p))",
            "if shutil.which('rhythmbox-client') and subprocess.call(['pgrep', '-x', 'rhythmbox'], stdout=subprocess.DEVNULL) == 0:",
            "    subprocess.Popen(['rhythmbox-client', '--play-uri=' + uri], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)",
            "elif shutil.which('rhythmbox'):",
            "    subprocess.Popen(['rhythmbox', p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)",
            "else:",
            "    subprocess.Popen(['xdg-open', p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)"
        ].join("\n")
        var safePy = pyPlay.replace(/'/g, "'\\''")
        executable.exec("python3 -c '" + safePy + "' '" + safePath + "'")
        triggerLiveActivity("Playing · " + item.name, "#F472B6")
    }

    function toggleLocalPlayPause() {
        if (root.currentLocalTrackPath.length === 0) {
            if (root.localMusicResults.length > 0) {
                playLocalTrackAtIndex(0)
            }
            return
        }
        root.localMusicPlaying = !root.localMusicPlaying
        var cmd = "if command -v rhythmbox-client >/dev/null 2>&1 && pgrep -x rhythmbox >/dev/null 2>&1; then " +
                  "rhythmbox-client --play-pause >/dev/null 2>&1 & fi"
        executable.exec(cmd)
    }

    function playNextLocalTrack() {
        if (root.localMusicResults.length === 0) return
        var nextIdx = (root.currentLocalTrackIndex + 1) % root.localMusicResults.length
        playLocalTrackAtIndex(nextIdx)
    }

    function playPrevLocalTrack() {
        if (root.localMusicResults.length === 0) return
        var prevIdx = root.currentLocalTrackIndex <= 0
            ? (root.localMusicResults.length - 1)
            : (root.currentLocalTrackIndex - 1)
        playLocalTrackAtIndex(prevIdx)
    }

    // =========================================================
    // GEMINI API ENGINE
    // =========================================================
    function handleGeminiResult(stdout, stderr) {
        root.isGeminiLoading = false
        var rawOut = stdout.trim()
        if (rawOut.length > 0) {
            try {
                var parsed = JSON.parse(rawOut)
                if (parsed.ok) {
                    root.activeModelUsed = parsed.model || root.preferredGeminiModel
                    root.geminiResponseText = (parsed.text || "").trim()
                    root.geminiErrorText = ""
                    return
                } else {
                    root.geminiErrorText = parsed.error || "Unknown API error."
                    return
                }
            } catch (e) {
                root.geminiErrorText = "Parse error: " + rawOut.substring(0, 220)
                return
            }
        }
        var rawErr = stderr.trim()
        root.geminiErrorText = rawErr.length > 0
            ? rawErr.substring(0, 240)
            : "No response received from Gemini endpoint."
    }

    function askGemini(promptText) {
        root.isOpen = true
        root.isGeminiLoading = true
        root.geminiResponseText = ""
        root.geminiErrorText = ""
        root.lastGeminiPrompt = promptText

        var hexPrompt = stringToHex(promptText)
        var safeKey = root.geminiApiKey.replace(/'/g, "'\\''")

        var pyScript = [
            "import sys, json, urllib.request, urllib.error, urllib.parse",
            "prompt = bytes.fromhex(sys.argv[1]).decode('utf-16-be')",
            "api_key = sys.argv[2]",
            "models = ['gemini-3.5-flash-lite', 'gemini-3.5-flash-lite-preview', 'gemini-3.5-flash', 'gemini-3-flash-preview']",
            "bases = [",
            "    'https://aiplatform.googleapis.com/v1/publishers/google/models',",
            "    'https://aiplatform.googleapis.com/v1beta1/publishers/google/models',",
            "    'https://generativelanguage.googleapis.com/v1beta/models'",
            "] if api_key.startswith('AQ.') else [",
            "    'https://generativelanguage.googleapis.com/v1beta/models',",
            "    'https://aiplatform.googleapis.com/v1/publishers/google/models'",
            "]",
            "payload = json.dumps({",
            "    'contents': [{'role': 'user', 'parts': [{'text': 'Answer concisely (under 120 words unless code/steps are needed): ' + prompt}]}],",
            "    'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 512}",
            "}).encode('utf-8')",
            "last_err = 'Request failed'",
            "for m in models:",
            "    for b in bases:",
            "        url = f'{b}/{m}:generateContent?key={urllib.parse.quote(api_key)}'",
            "        req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'}, method='POST')",
            "        try:",
            "            with urllib.request.urlopen(req, timeout=20) as resp:",
            "                data = json.loads(resp.read().decode('utf-8'))",
            "                parts = data.get('candidates', [{}])[0].get('content', {}).get('parts', [])",
            "                txt = ''.join(p.get('text', '') for p in parts).strip()",
            "                if txt:",
            "                    print(json.dumps({'ok': True, 'model': m, 'text': txt}))",
            "                    sys.exit(0)",
            "                last_err = 'Empty response from ' + m",
            "        except urllib.error.HTTPError as e:",
            "            body = e.read().decode('utf-8', errors='ignore')",
            "            msg = body",
            "            try:",
            "                msg = json.loads(body).get('error', {}).get('message', body)",
            "            except Exception:",
            "                pass",
            "            last_err = f'HTTP {e.code} ({m}): {msg}'",
            "            if e.code in (401, 403, 404):",
            "                continue",
            "        except Exception as e:",
            "            last_err = f'{type(e).__name__}: {e}'",
            "print(json.dumps({'ok': False, 'error': last_err}))"
        ].join("\n")

        var safePy = pyScript.replace(/'/g, "'\\''")
        var cmd = "python3 -c '" + safePy + "' '" + hexPrompt + "' '" + safeKey + "'"
        geminiExecutable.exec(cmd)
    }

    function performSearch(rawText) {
        if (!rawText) return
        var raw = rawText.trim()
        if (raw.length === 0) return

        var engine = engines[currentEngineIndex]
        var query = raw

        for (var i = 0; i < engines.length; i++) {
            var prefix = engines[i].bang + " "
            if (prefix.length > 1 && raw.toLowerCase().indexOf(prefix) === 0) {
                engine = engines[i]
                query = raw.substring(prefix.length).trim()
                break
            }
        }

        if (query.length === 0) return

        if (engine.name === "Note") {
            saveNote(query, "")
            if (!root.pinnedOpen) {
                root.isOpen = false
            }
            return
        }

        if (engine.name === "Gemini" && !looksLikeUrl(query)) {
            askGemini(query)
            return
        }

        var fallbackUrl = engine.url && engine.url.length > 0 ? engine.url : "https://www.google.com/search?q="
        var fallbackName = engine.url && engine.url.length > 0 ? engine.name : "Google"

        var targetUrl = ""
        var activityBadge = ""
        var activityTone = engine.color

        if (looksLikeUrl(query)) {
            targetUrl = /^https?:\/\//i.test(query) ? query : "https://" + query
            activityBadge = "Opening URL"
            activityTone = "#34D399"
        } else {
            targetUrl = fallbackUrl + encodeURIComponent(query)
            activityBadge = fallbackName + " · " + (query.length > 18 ? query.substring(0, 18) + "…" : query)
        }

        var safeUrl = targetUrl.replace(/'/g, "'\\''")
        var cmd = "PATH=\"/snap/bin:/usr/local/bin:/usr/bin:/bin:$PATH\"; " +
                  "if command -v firefox >/dev/null 2>&1; then " +
                  "nohup firefox '" + safeUrl + "' >/dev/null 2>&1 & " +
                  "else xdg-open '" + safeUrl + "' >/dev/null 2>&1 & fi"
        executable.exec(cmd)

        triggerLiveActivity(activityBadge, activityTone)

        if (!root.pinnedOpen) {
            root.isOpen = false
        }
    }

    fullRepresentation: Item {
        id: islandRoot
        implicitWidth: Kirigami.Units.gridUnit * 35
        implicitHeight: Kirigami.Units.gridUnit * 20
        focus: root.isOpen

        Keys.onTabPressed: function(event) {
            if (root.isOpen) {
                root.cycleEngine()
                event.accepted = true
            }
        }
        Keys.onEscapePressed: function(event) {
            if (root.isOpen) {
                islandRoot.closeIsland()
                event.accepted = true
            }
        }

        readonly property string currentQuery: searchInput ? searchInput.text.trim() : ""
        readonly property bool isBang: /^!(yt|gh|ddg|ai|note|g)\s+/i.test(currentQuery)
        readonly property bool isUrl: !isBang && currentQuery.length > 0 && root.looksLikeUrl(currentQuery)
        readonly property string activeTabName: root.engines[root.currentEngineIndex].name

        readonly property bool isGeminiActive: activeTabName === "Gemini" || /^!ai\s+/i.test(currentQuery)
        readonly property bool isNoteActive: activeTabName === "Note"
        readonly property bool isMusicActive: activeTabName === "Music"

        readonly property bool showCompactMusicProgress: root.currentLocalTrackPath.length > 0 && (root.localMusicPlaying || isMusicActive)
        readonly property real trackProgressRatio: root.localTrackDurationSec > 0
            ? Math.max(0.0, Math.min(1.0, root.localTrackElapsedSec / root.localTrackDurationSec))
            : (root.localMusicPlaying ? 0.14 : 0.0)

        readonly property bool showSearchBar: !isNoteActive && !isMusicActive
        readonly property bool hasGeminiDrawer: showSearchBar && (root.isGeminiLoading || root.geminiResponseText.length > 0 || root.geminiErrorText.length > 0)

        readonly property color statusAccent: isBang
            ? (/^!ai\s+/i.test(currentQuery) ? "#38BDF8" : (/^!note\s+/i.test(currentQuery) ? "#34D399" : "#FBBF24"))
            : (isUrl ? "#34D399" : root.activeAccent)

        readonly property string statusLabel: isBang
            ? (/^!ai\s+/i.test(currentQuery) ? "Gemini" : (/^!note\s+/i.test(currentQuery) ? "Quick Note" : "Bang"))
            : (isUrl ? "Direct URL" : activeTabName)

        readonly property color indicatorDotColor: root.isOpen
            ? statusAccent
            : (root.liveActivityText.length > 0 ? root.liveActivityColor : (showCompactMusicProgress ? "#F472B6" : root.activeAccent))

        readonly property real compactWidth: Math.min(Math.max(240, islandRoot.width - 16), (root.liveActivityText.length > 0 || showCompactMusicProgress) ? 316 : 254)
        readonly property real expandedWidth: Math.min(Math.max(460, islandRoot.width - 16), 536)

        readonly property real desiredExpandedHeight: {
            if (isNoteActive) return 194
            if (isMusicActive) return 274
            if (hasGeminiDrawer) {
                return root.isGeminiLoading ? 174 : Math.min(260, Math.max(190, 122 + geminiTextMeasure.implicitHeight + 48))
            }
            return 114
        }

        readonly property real maxAvailableHeight: islandRoot.height > 60 ? (islandRoot.height - 12) : desiredExpandedHeight
        readonly property real targetWidth: root.isOpen ? expandedWidth : compactWidth
        readonly property real targetHeight: root.isOpen ? Math.min(desiredExpandedHeight, maxAvailableHeight) : 38

        property bool copiedRecently: false

        TextEdit {
            id: clipboardHelper
            visible: false
        }

        Text {
            id: geminiTextMeasure
            visible: false
            width: islandRoot.expandedWidth - 52
            text: root.geminiErrorText.length > 0 ? root.geminiErrorText : root.geminiResponseText
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Timer {
            id: copyFeedbackTimer
            interval: 1500
            repeat: false
            onTriggered: islandRoot.copiedRecently = false
        }

        Timer {
            id: localSearchDebounce
            interval: 150
            repeat: false
            onTriggered: root.searchLocalMusic(localMusicInput ? localMusicInput.text : "")
        }

        Timer {
            id: focusDelayTimer
            interval: 45
            repeat: false
            onTriggered: {
                if (islandRoot.isNoteActive && noteBodyArea) {
                    noteBodyArea.forceActiveFocus()
                } else if (islandRoot.isMusicActive && localMusicInput) {
                    localMusicInput.forceActiveFocus()
                } else if (islandRoot.showSearchBar && searchInput) {
                    searchInput.forceActiveFocus()
                }
            }
        }

        Connections {
            target: root
            function onShortcutTriggered() {
                if (!root.isOpen) {
                    islandRoot.openIsland()
                } else if (islandRoot.showSearchBar && searchInput && !searchInput.activeFocus) {
                    focusDelayTimer.restart()
                } else if (islandRoot.isNoteActive && noteBodyArea && !noteBodyArea.activeFocus) {
                    focusDelayTimer.restart()
                } else if (islandRoot.isMusicActive && localMusicInput && !localMusicInput.activeFocus) {
                    focusDelayTimer.restart()
                } else if (!root.pinnedOpen) {
                    islandRoot.closeIsland()
                }
            }
        }

        function openIsland() {
            root.isOpen = true
            if (islandRoot.isMusicActive && !root.localMusicLoadedOnce) {
                root.searchLocalMusic("")
            }
            focusDelayTimer.restart()
        }

        function closeIsland() {
            root.isOpen = false
        }

        function submitSearch() {
            if (!searchInput || searchInput.text.trim().length === 0) return
            root.performSearch(searchInput.text)
            searchInput.text = ""
        }

        function submitNote() {
            var body = noteBodyArea ? noteBodyArea.text : ""
            if (body.trim().length === 0) return
            var title = noteTitleInput ? noteTitleInput.text : ""
            root.saveNote(body, title)
            if (noteBodyArea) noteBodyArea.text = ""
            if (noteTitleInput) noteTitleInput.text = ""
        }

        function copyResponse() {
            var toCopy = root.geminiErrorText.length > 0 ? root.geminiErrorText : root.geminiResponseText
            if (toCopy.length === 0) return
            clipboardHelper.text = toCopy
            clipboardHelper.selectAll()
            clipboardHelper.copy()
            islandRoot.copiedRecently = true
            copyFeedbackTimer.restart()
        }

        // Architectural Ambient Drop Shadow Ring
        Rectangle {
            anchors.fill: islandShell
            anchors.margins: root.isOpen ? -5 : -3
            radius: islandShell.radius + (root.isOpen ? 5 : 3)
            color: "#000000"
            opacity: root.isOpen ? 0.34 : 0.22

            Behavior on opacity { NumberAnimation { duration: 220 } }
            Behavior on anchors.margins { NumberAnimation { duration: 220 } }
        }

        // Morphing Satin Obsidian Dynamic Island Body
        Rectangle {
            id: islandShell
            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter

            width: islandRoot.targetWidth
            height: islandRoot.targetHeight
            radius: root.isOpen ? 20 : 19
            clip: true

            scale: (!root.isOpen && compactMouse.pressed) ? 0.97 : ((!root.isOpen && compactHover.hovered) ? 1.015 : 1.0)

            Behavior on width {
                SpringAnimation {
                    spring: 5.0
                    damping: 0.36
                }
            }
            Behavior on height {
                SpringAnimation {
                    spring: 5.0
                    damping: 0.36
                }
            }
            Behavior on radius {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation { duration: 110 }
            }

            gradient: Gradient {
                GradientStop { position: 0.0; color: "#F714161B" }
                GradientStop { position: 1.0; color: "#FA0B0C0F" }
            }

            border.width: 1
            border.color: root.isOpen
                ? Qt.rgba(1, 1, 1, 0.16)
                : (compactHover.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.11))

            Behavior on border.color { ColorAnimation { duration: 180 } }

            // Subtle anodized top catchlight rim
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Qt.rgba(1, 1, 1, 0.16)
            }

            // Subtle top-down glass sheen
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.isOpen ? 40 : 18
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.05) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }

            // =========================================================
            // STATE 1: COMPACT DYNAMIC ISLAND CAPSULE
            // =========================================================
            Item {
                id: compactView
                anchors.fill: parent
                opacity: root.isOpen ? 0.0 : 1.0
                visible: opacity > 0.02

                Behavior on opacity { NumberAnimation { duration: 140 } }

                // Ambient translucent playback wash across played portion
                Rectangle {
                    id: compactProgressWash
                    visible: islandRoot.showCompactMusicProgress
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    width: parent.width * islandRoot.trackProgressRatio

                    Behavior on width {
                        NumberAnimation { duration: 480; easing.type: Easing.Linear }
                    }

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: root.localMusicPlaying
                                ? Qt.rgba(0.96, 0.45, 0.71, 0.14)
                                : Qt.rgba(0.96, 0.45, 0.71, 0.06)
                        }
                        GradientStop {
                            position: 1.0
                            color: root.localMusicPlaying
                                ? Qt.rgba(0.96, 0.45, 0.71, 0.04)
                                : Qt.rgba(0.96, 0.45, 0.71, 0.02)
                        }
                    }

                    // Crisp vertical leading edge highlight
                    Rectangle {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        width: 1
                        color: root.localMusicPlaying
                            ? Qt.rgba(0.96, 0.45, 0.71, 0.24)
                            : Qt.rgba(0.96, 0.45, 0.71, 0.10)
                    }
                }

                // Precision bottom-edge capsule progress bar
                Item {
                    visible: islandRoot.showCompactMusicProgress
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 6

                    // Subtle unplayed track groove
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 2.5
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    // Soft ambient glow halo above the active bar
                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        width: compactActiveProgressBar.width
                        height: 6
                        opacity: root.localMusicPlaying ? 0.26 : 0.0
                        color: "#F472B6"
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                    }

                    // Luminous pink progress fill
                    Rectangle {
                        id: compactActiveProgressBar
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        height: 2.5
                        width: parent.width * islandRoot.trackProgressRatio

                        Behavior on width {
                            NumberAnimation { duration: 480; easing.type: Easing.Linear }
                        }

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0.0
                                color: root.localMusicPlaying ? "#DB2777" : Qt.rgba(0.96, 0.45, 0.71, 0.42)
                            }
                            GradientStop {
                                position: 0.85
                                color: root.localMusicPlaying ? "#F472B6" : Qt.rgba(0.96, 0.45, 0.71, 0.50)
                            }
                            GradientStop {
                                position: 1.0
                                color: root.localMusicPlaying ? "#FBCFE8" : Qt.rgba(0.96, 0.45, 0.71, 0.55)
                            }
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        radius: 11
                        color: islandRoot.showCompactMusicProgress && root.localMusicPlaying
                            ? Qt.rgba(0.96, 0.45, 0.71, 0.14)
                            : Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: islandRoot.showCompactMusicProgress && root.localMusicPlaying
                            ? Qt.rgba(0.96, 0.45, 0.71, 0.35)
                            : Qt.rgba(1, 1, 1, 0.09)

                        Kirigami.Icon {
                            visible: !islandRoot.isGeminiActive && !islandRoot.isNoteActive && !islandRoot.isMusicActive && !islandRoot.showCompactMusicProgress
                            anchors.centerIn: parent
                            source: "firefox"
                            width: 15
                            height: 15
                        }

                        Kirigami.Icon {
                            visible: islandRoot.isGeminiActive && !islandRoot.showCompactMusicProgress
                            anchors.centerIn: parent
                            source: "starred-symbolic"
                            isMask: true
                            color: "#38BDF8"
                            width: 13
                            height: 13
                        }

                        Kirigami.Icon {
                            visible: islandRoot.isNoteActive && !islandRoot.showCompactMusicProgress
                            anchors.centerIn: parent
                            source: "document-edit-symbolic"
                            isMask: true
                            color: "#34D399"
                            width: 13
                            height: 13
                        }

                        Kirigami.Icon {
                            visible: islandRoot.isMusicActive || islandRoot.showCompactMusicProgress
                            anchors.centerIn: parent
                            source: "folder-music-symbolic"
                            isMask: true
                            color: "#F472B6"
                            width: 13
                            height: 13
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.liveActivityText.length > 0
                            ? root.liveActivityText
                            : (islandRoot.showCompactMusicProgress
                                ? root.currentLocalTrackName
                                : (islandRoot.isNoteActive
                                    ? "Write a note..."
                                    : (islandRoot.isGeminiActive
                                        ? "Ask Gemini..."
                                        : (islandRoot.isMusicActive ? "Local music..." : "Search or enter URL..."))))
                        color: (root.liveActivityText.length > 0 || (islandRoot.showCompactMusicProgress && root.localMusicPlaying))
                            ? "#F4F4F5"
                            : (islandRoot.showCompactMusicProgress ? "#D4D4D8" : "#A1A1AA")
                        font.pixelSize: 12
                        font.weight: (root.liveActivityText.length > 0 || (islandRoot.showCompactMusicProgress && root.localMusicPlaying))
                            ? Font.Medium
                            : Font.Normal
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        Layout.preferredWidth: compactBadgeRow.implicitWidth + 14
                        Layout.preferredHeight: 20
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: islandRoot.showCompactMusicProgress && root.localMusicPlaying
                            ? Qt.rgba(0.96, 0.45, 0.71, 0.25)
                            : Qt.rgba(1, 1, 1, 0.09)

                        Row {
                            id: compactBadgeRow
                            anchors.centerIn: parent
                            spacing: 4

                            // Animated 3-bar audio equalizer when playing
                            Row {
                                visible: islandRoot.showCompactMusicProgress && root.localMusicPlaying
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter

                                Repeater {
                                    model: 3
                                    Rectangle {
                                        width: 2
                                        height: 8
                                        radius: 1
                                        color: "#F472B6"
                                        anchors.bottom: parent.bottom
                                        SequentialAnimation on height {
                                            loops: Animation.Infinite
                                            running: islandRoot.showCompactMusicProgress && root.localMusicPlaying && !root.isOpen
                                            PauseAnimation { duration: index * 140 }
                                            NumberAnimation { from: 3; to: 10; duration: 280 }
                                            NumberAnimation { from: 10; to: 4; duration: 280 }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: !(islandRoot.showCompactMusicProgress && root.localMusicPlaying)
                                width: 5
                                height: 5
                                radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: islandRoot.indicatorDotColor
                            }

                            Text {
                                text: root.liveActivityText.length > 0
                                    ? "Done"
                                    : (islandRoot.showCompactMusicProgress
                                        ? (root.localTrackDurationSec > 0
                                            ? root.formatSeconds(root.localTrackElapsedSec)
                                            : (root.localMusicPlaying ? "Playing" : "Paused"))
                                        : root.engines[root.currentEngineIndex].short)
                                color: "#E4E4E7"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }
                        }
                    }
                }

                MouseArea {
                    id: compactMouse
                    anchors.fill: parent
                    enabled: !root.isOpen
                    cursorShape: Qt.PointingHandCursor
                    onClicked: islandRoot.openIsland()
                }
                HoverHandler { id: compactHover }
            }

            // =========================================================
            // STATE 2: EXPANDED STUDIO COMMAND DECK
            // =========================================================
            ColumnLayout {
                id: expandedView
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 6

                opacity: root.isOpen ? 1.0 : 0.0
                visible: opacity > 0.02

                Behavior on opacity { NumberAnimation { duration: 180 } }

                // ---------------------------------------------------------
                // 1. TOP ARCHITECTURAL HEADER BAR (Fixed 20px)
                // ---------------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    Layout.maximumHeight: 20
                    spacing: 7

                    Kirigami.Icon {
                        visible: !islandRoot.isGeminiActive && !islandRoot.isNoteActive && !islandRoot.isMusicActive
                        source: "firefox"
                        Layout.preferredWidth: 15
                        Layout.preferredHeight: 15
                    }

                    Kirigami.Icon {
                        visible: islandRoot.isGeminiActive
                        source: "starred-symbolic"
                        isMask: true
                        color: "#38BDF8"
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                    }

                    Kirigami.Icon {
                        visible: islandRoot.isNoteActive
                        source: "document-edit-symbolic"
                        isMask: true
                        color: "#34D399"
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                    }

                    Kirigami.Icon {
                        visible: islandRoot.isMusicActive
                        source: "folder-music-symbolic"
                        isMask: true
                        color: "#F472B6"
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                    }

                    Text {
                        text: islandRoot.isGeminiActive
                            ? "Gemini Assistant"
                            : (islandRoot.isNoteActive
                                ? "Quick Notes"
                                : (islandRoot.isMusicActive ? "Local Music" : "Quick Launcher"))
                        color: "#A1A1AA"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    Rectangle {
                        Layout.preferredWidth: hudRow.implicitWidth + 12
                        Layout.preferredHeight: 18
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.09)

                        Row {
                            id: hudRow
                            anchors.centerIn: parent
                            spacing: 5

                            Rectangle {
                                width: 5
                                height: 5
                                radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: islandRoot.statusAccent
                            }

                            Text {
                                text: islandRoot.statusLabel
                                color: "#D4D4D8"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Pin Button
                    Rectangle {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 20
                        radius: 6
                        color: root.pinnedOpen
                            ? Qt.rgba(1, 1, 1, 0.14)
                            : (pinHover.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent")
                        border.width: root.pinnedOpen ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.18)

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "window-pin-symbolic"
                            isMask: true
                            color: root.pinnedOpen ? "#FAFAFA" : "#71717A"
                            width: 12
                            height: 12
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.pinnedOpen = !root.pinnedOpen; islandRoot.forceActiveFocus() }
                        }

                        QQC2.ToolTip.visible: pinHover.hovered
                        QQC2.ToolTip.text: root.pinnedOpen ? "Unpin island" : "Keep island open"
                        HoverHandler { id: pinHover }
                    }

                    // Collapse Button
                    Rectangle {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 20
                        radius: 6
                        color: closeHover.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "list-remove-symbolic"
                            isMask: true
                            color: closeHover.hovered ? "#FAFAFA" : "#71717A"
                            width: 12
                            height: 12
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: islandRoot.closeIsland()
                        }

                        QQC2.ToolTip.visible: closeHover.hovered
                        QQC2.ToolTip.text: "Collapse (Esc)"
                        HoverHandler { id: closeHover }
                    }
                }

                // ---------------------------------------------------------
                // 2A. SEARCH & GEMINI INPUT BAR
                // ---------------------------------------------------------
                RowLayout {
                    visible: islandRoot.showSearchBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    Layout.maximumHeight: 34
                    spacing: 8

                    QQC2.TextField {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        placeholderText: islandRoot.isGeminiActive
                            ? "Ask Gemini anything..."
                            : ("Search " + root.engines[root.currentEngineIndex].name + " or enter URL...")
                        color: "#FAFAFA"
                        placeholderTextColor: "#52525B"
                        font.pixelSize: 15
                        font.weight: Font.Normal
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        background: Item {}

                        onActiveFocusChanged: root.inputActive = activeFocus
                        onAccepted: islandRoot.submitSearch()
                        Keys.onReturnPressed: islandRoot.submitSearch()
                        Keys.onEnterPressed: islandRoot.submitSearch()
                        Keys.onTabPressed: function(event) {
                            root.cycleEngine()
                            event.accepted = true
                        }
                        Keys.onEscapePressed: function(event) {
                            if (islandRoot.hasGeminiDrawer) {
                                root.clearGeminiDrawer()
                            } else {
                                islandRoot.closeIsland()
                            }
                            event.accepted = true
                        }
                    }

                    Rectangle {
                        visible: searchInput.text.length > 0
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: 10
                        color: clearHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "edit-clear-symbolic"
                            isMask: true
                            color: "#A1A1AA"
                            width: 11
                            height: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchInput.text = ""
                                searchInput.forceActiveFocus()
                            }
                        }
                        HoverHandler { id: clearHover }
                    }

                    Rectangle {
                        Layout.preferredWidth: 66
                        Layout.preferredHeight: 28
                        radius: 14
                        color: searchInput.text.length > 0 ? "#F4F4F5" : Qt.rgba(1, 1, 1, 0.06)
                        border.width: searchInput.text.length > 0 ? 0 : 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        scale: launchMouse.pressed ? 0.96 : (launchHover.hovered ? 1.02 : 1.0)

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 90 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: islandRoot.isGeminiActive ? "Ask" : "Open"
                                color: searchInput.text.length > 0 ? "#09090B" : "#71717A"
                                font.weight: Font.DemiBold
                                font.pixelSize: 11
                            }
                            Text {
                                text: "↵"
                                color: searchInput.text.length > 0 ? "#3F3F46" : "#52525B"
                                font.weight: Font.Normal
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: launchMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: islandRoot.submitSearch()
                        }
                        HoverHandler { id: launchHover }
                    }
                }

                // ---------------------------------------------------------
                // 2B. DEDICATED NOTE COMPOSER
                // ---------------------------------------------------------
                ColumnLayout {
                    visible: islandRoot.isNoteActive
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        Layout.maximumHeight: 24
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 7
                            color: Qt.rgba(0, 0, 0, 0.34)
                            border.width: 1
                            border.color: noteTitleInput.activeFocus ? Qt.rgba(0.20, 0.83, 0.60, 0.45) : Qt.rgba(1, 1, 1, 0.08)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 4

                                Text {
                                    text: root.activeNotesDir + "/"
                                    color: "#71717A"
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                }

                                QQC2.TextField {
                                    id: noteTitleInput
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    placeholderText: "filename.txt (optional)"
                                    color: "#E4E4E7"
                                    placeholderTextColor: "#52525B"
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    verticalAlignment: TextInput.AlignVCenter
                                    background: Item {}

                                    Keys.onTabPressed: function(event) {
                                        root.cycleEngine()
                                        event.accepted = true
                                    }
                                    Keys.onEscapePressed: function(event) {
                                        islandRoot.closeIsland()
                                        event.accepted = true
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: openDirRow.implicitWidth + 12
                            Layout.fillHeight: true
                            radius: 7
                            color: openDirHover.hovered ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.05)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.09)

                            Row {
                                id: openDirRow
                                anchors.centerIn: parent
                                spacing: 4

                                Kirigami.Icon {
                                    source: "folder-open-symbolic"
                                    isMask: true
                                    color: "#A1A1AA"
                                    width: 11
                                    height: 11
                                }

                                Text {
                                    text: "Folder"
                                    color: "#D4D4D8"
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNotesFolder()
                            }
                            HoverHandler { id: openDirHover }
                        }

                        Rectangle {
                            readonly property bool canSave: noteBodyArea && noteBodyArea.text.trim().length > 0
                            Layout.preferredWidth: 68
                            Layout.fillHeight: true
                            radius: 12
                            color: canSave ? "#F4F4F5" : Qt.rgba(1, 1, 1, 0.06)
                            border.width: canSave ? 0 : 1
                            border.color: Qt.rgba(1, 1, 1, 0.09)

                            Text {
                                anchors.centerIn: parent
                                text: "Save .txt"
                                color: parent.canSave ? "#09090B" : "#71717A"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: islandRoot.submitNote()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.28)
                        border.width: 1
                        border.color: noteBodyArea.activeFocus ? Qt.rgba(0.20, 0.83, 0.60, 0.40) : Qt.rgba(1, 1, 1, 0.07)

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 8
                            contentWidth: width
                            contentHeight: noteBodyArea.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            QQC2.TextArea {
                                id: noteBodyArea
                                width: parent.width
                                placeholderText: root.noteStatusText.length > 0
                                    ? root.noteStatusText
                                    : "Write your note here... (Ctrl+Enter to save as .txt)"
                                color: "#F4F4F5"
                                placeholderTextColor: root.noteStatusText.length > 0
                                    ? (root.noteStatusError ? "#FDA4AF" : "#34D399")
                                    : "#52525B"
                                font.pixelSize: 12
                                wrapMode: TextEdit.WordWrap
                                selectByMouse: true
                                background: Item {}

                                Keys.onTabPressed: function(event) {
                                    root.cycleEngine()
                                    event.accepted = true
                                }
                                Keys.onPressed: function(event) {
                                    if ((event.modifiers & Qt.ControlModifier) &&
                                        (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                        islandRoot.submitNote()
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Escape) {
                                        islandRoot.closeIsland()
                                        event.accepted = true
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // 2C. LOCAL MUSIC PLAYER & LIBRARY BROWSER
                // ---------------------------------------------------------
                Rectangle {
                    visible: islandRoot.isMusicActive
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.03)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.07)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 6

                        // Selected Local Track Header + Transport Controls
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            Layout.maximumHeight: 44
                            spacing: 10

                            // Music Icon Housing
                            Rectangle {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42
                                radius: 10
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.width: 1
                                border.color: root.localMusicPlaying
                                    ? Qt.rgba(0.96, 0.45, 0.71, 0.40)
                                    : Qt.rgba(1, 1, 1, 0.10)

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    source: "folder-music-symbolic"
                                    isMask: true
                                    color: root.localMusicPlaying ? "#F472B6" : "#A1A1AA"
                                    width: 19
                                    height: 19
                                }
                            }

                            // Track Name & Folder
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                Row {
                                    spacing: 5

                                    Rectangle {
                                        width: 5
                                        height: 5
                                        radius: 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root.localMusicPlaying ? "#F472B6" : "#71717A"
                                    }

                                    Text {
                                        text: root.currentLocalTrackPath.length > 0
                                            ? (root.localMusicPlaying ? "Rhythmbox · Playing" : "Rhythmbox · Paused")
                                            : "Local Library"
                                        color: root.localMusicPlaying ? "#F472B6" : "#A1A1AA"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.currentLocalTrackName
                                    color: "#FAFAFA"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.currentLocalTrackFolder
                                    color: "#71717A"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            // Local Playlist Transport Controls (Prev / Play-Pause / Next)
                            Row {
                                spacing: 5
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: prevHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.09)
                                    scale: prevMouse.pressed ? 0.92 : 1.0

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: "media-skip-backward-symbolic"
                                        isMask: true
                                        color: "#E4E4E7"
                                        width: 12
                                        height: 12
                                    }

                                    MouseArea {
                                        id: prevMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.playPrevLocalTrack()
                                    }
                                    HoverHandler { id: prevHover }
                                }

                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: playHover.hovered ? "#FFFFFF" : "#F4F4F5"
                                    scale: playMouse.pressed ? 0.92 : 1.0

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: root.localMusicPlaying ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
                                        isMask: true
                                        color: "#09090B"
                                        width: 14
                                        height: 14
                                    }

                                    MouseArea {
                                        id: playMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleLocalPlayPause()
                                    }
                                    HoverHandler { id: playHover }
                                }

                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: nextHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.09)
                                    scale: nextMouse.pressed ? 0.92 : 1.0

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: "media-skip-forward-symbolic"
                                        isMask: true
                                        color: "#E4E4E7"
                                        width: 12
                                        height: 12
                                    }

                                    MouseArea {
                                        id: nextMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.playNextLocalTrack()
                                    }
                                    HoverHandler { id: nextHover }
                                }
                            }
                        }

                        // Scrubbable Expanded Progress Bar + Elapsed/Total Time
                        RowLayout {
                            visible: root.currentLocalTrackPath.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 12
                            Layout.maximumHeight: 12
                            spacing: 8

                            Text {
                                text: root.formatSeconds(root.localTrackElapsedSec)
                                color: "#A1A1AA"
                                font.pixelSize: 9
                                font.family: "monospace"
                            }

                            Item {
                                id: expandedScrubTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 10

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: scrubHover.hovered ? 4 : 3
                                    radius: 2
                                    color: Qt.rgba(1, 1, 1, 0.09)
                                    Behavior on height { NumberAnimation { duration: 100 } }

                                    Rectangle {
                                        width: parent.width * islandRoot.trackProgressRatio
                                        height: parent.height
                                        radius: 2
                                        color: "#F472B6"
                                        Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.Linear } }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        if (expandedScrubTrack.width > 0) {
                                            root.seekLocalTrack(mouse.x / expandedScrubTrack.width)
                                        }
                                    }
                                }
                                HoverHandler { id: scrubHover }
                            }

                            Text {
                                text: root.localTrackDurationSec > 0 ? root.formatSeconds(root.localTrackDurationSec) : "--:--"
                                color: "#71717A"
                                font.pixelSize: 9
                                font.family: "monospace"
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Qt.rgba(1, 1, 1, 0.07)
                        }

                        // Instant Local Music Search Box
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            Layout.maximumHeight: 26
                            radius: 8
                            color: Qt.rgba(0, 0, 0, 0.34)
                            border.width: 1
                            border.color: localMusicInput.activeFocus
                                ? Qt.rgba(0.96, 0.45, 0.71, 0.48)
                                : Qt.rgba(1, 1, 1, 0.08)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 6

                                Kirigami.Icon {
                                    source: "search-symbolic"
                                    isMask: true
                                    color: "#71717A"
                                    Layout.preferredWidth: 12
                                    Layout.preferredHeight: 12
                                }

                                QQC2.TextField {
                                    id: localMusicInput
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    placeholderText: "Search local songs in ~/Music, ~/Downloads..."
                                    color: "#FAFAFA"
                                    placeholderTextColor: "#52525B"
                                    font.pixelSize: 11
                                    verticalAlignment: TextInput.AlignVCenter
                                    selectByMouse: true
                                    background: Item {}

                                    onTextChanged: localSearchDebounce.restart()
                                    onAccepted: {
                                        if (root.localMusicResults.length > 0) {
                                            root.playLocalTrackAtIndex(0)
                                        }
                                    }
                                    Keys.onTabPressed: function(event) {
                                        root.cycleEngine()
                                        event.accepted = true
                                    }
                                    Keys.onEscapePressed: function(event) {
                                        islandRoot.closeIsland()
                                        event.accepted = true
                                    }
                                }

                                Text {
                                    visible: root.localMusicResults.length > 0
                                    text: root.localMusicResults.length + (root.localMusicResults.length === 1 ? " track" : " tracks")
                                    color: "#71717A"
                                    font.pixelSize: 9
                                }

                                Rectangle {
                                    visible: localMusicInput.text.length > 0
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    radius: 8
                                    color: clearLocalHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: "edit-clear-symbolic"
                                        isMask: true
                                        color: "#A1A1AA"
                                        width: 9
                                        height: 9
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            localMusicInput.text = ""
                                            localMusicInput.forceActiveFocus()
                                        }
                                    }
                                    HoverHandler { id: clearLocalHover }
                                }
                            }
                        }

                        // Local Track Results List
                        ListView {
                            id: localMusicListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 3
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.localMusicResults

                            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                                policy: QQC2.ScrollBar.AsNeeded
                            }

                            delegate: Rectangle {
                                readonly property bool isSelectedTrack: index === root.currentLocalTrackIndex
                                width: localMusicListView.width - 4
                                height: 26
                                radius: 7
                                color: isSelectedTrack
                                    ? Qt.rgba(0.96, 0.45, 0.71, 0.14)
                                    : (trackRowHover.hovered ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.025))
                                border.width: 1
                                border.color: isSelectedTrack
                                    ? Qt.rgba(0.96, 0.45, 0.71, 0.35)
                                    : (trackRowHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 7

                                    Kirigami.Icon {
                                        source: "media-playback-start-symbolic"
                                        isMask: true
                                        color: (isSelectedTrack || trackRowHover.hovered) ? "#F472B6" : "#71717A"
                                        Layout.preferredWidth: 11
                                        Layout.preferredHeight: 11
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        color: (isSelectedTrack || trackRowHover.hovered) ? "#FAFAFA" : "#E4E4E7"
                                        font.pixelSize: 11
                                        font.weight: (isSelectedTrack || trackRowHover.hovered) ? Font.Medium : Font.Normal
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: modelData.folder
                                        color: "#71717A"
                                        font.pixelSize: 9
                                        elide: Text.ElideMiddle
                                        Layout.maximumWidth: 110
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.playLocalTrackAtIndex(index)
                                }
                                HoverHandler { id: trackRowHover }
                            }

                            Text {
                                visible: root.localMusicResults.length === 0
                                anchors.centerIn: parent
                                text: root.isLocalMusicSearching
                                    ? "Scanning local audio folders..."
                                    : "No matching audio files found in ~/Music or ~/Downloads"
                                color: "#71717A"
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // 2D. INLINE GEMINI RESPONSE DRAWER
                // ---------------------------------------------------------
                Rectangle {
                    id: geminiDrawer
                    visible: islandRoot.hasGeminiDrawer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: root.geminiErrorText.length > 0
                        ? Qt.rgba(0.96, 0.25, 0.37, 0.08)
                        : Qt.rgba(1, 1, 1, 0.035)
                    border.width: 1
                    border.color: root.geminiErrorText.length > 0
                        ? Qt.rgba(0.96, 0.25, 0.37, 0.28)
                        : Qt.rgba(1, 1, 1, 0.08)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
                            spacing: 6

                            Rectangle {
                                width: 5
                                height: 5
                                radius: 3
                                color: root.geminiErrorText.length > 0 ? "#F87171" : "#38BDF8"
                            }

                            Text {
                                text: root.isGeminiLoading
                                    ? "Thinking..."
                                    : (root.geminiErrorText.length > 0 ? "API Notice" : root.activeModelUsed)
                                color: root.geminiErrorText.length > 0 ? "#FDA4AF" : "#A1A1AA"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                visible: !root.isGeminiLoading && (root.geminiResponseText.length > 0 || root.geminiErrorText.length > 0)
                                Layout.preferredWidth: copyRow.implicitWidth + 12
                                Layout.preferredHeight: 18
                                radius: 5
                                color: islandRoot.copiedRecently ? Qt.rgba(0.20, 0.83, 0.60, 0.16) : Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1
                                border.color: islandRoot.copiedRecently ? Qt.rgba(0.20, 0.83, 0.60, 0.35) : Qt.rgba(1, 1, 1, 0.10)

                                Row {
                                    id: copyRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Kirigami.Icon {
                                        source: "edit-copy-symbolic"
                                        isMask: true
                                        color: islandRoot.copiedRecently ? "#34D399" : "#A1A1AA"
                                        width: 10
                                        height: 10
                                    }

                                    Text {
                                        text: islandRoot.copiedRecently ? "Copied" : "Copy"
                                        color: islandRoot.copiedRecently ? "#34D399" : "#D4D4D8"
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: islandRoot.copyResponse()
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                radius: 5
                                color: dismissHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    source: "edit-clear-symbolic"
                                    isMask: true
                                    color: dismissHover.hovered ? "#FAFAFA" : "#71717A"
                                    width: 10
                                    height: 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.clearGeminiDrawer()
                                        searchInput.forceActiveFocus()
                                    }
                                }
                                HoverHandler { id: dismissHover }
                            }
                        }

                        Row {
                            visible: root.isGeminiLoading
                            spacing: 5
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 5
                                    height: 5
                                    radius: 3
                                    color: "#71717A"
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: index * 180 }
                                        NumberAnimation { from: 0.25; to: 1.0; duration: 400 }
                                        NumberAnimation { from: 1.0; to: 0.25; duration: 400 }
                                    }
                                }
                            }

                            Text {
                                text: "Generating response..."
                                color: "#71717A"
                                font.pixelSize: 11
                            }
                        }

                        Flickable {
                            visible: !root.isGeminiLoading
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: responseTextDisplay.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                                policy: QQC2.ScrollBar.AsNeeded
                            }

                            TextEdit {
                                id: responseTextDisplay
                                width: parent.width - 8
                                text: root.geminiErrorText.length > 0 ? root.geminiErrorText : root.geminiResponseText
                                color: root.geminiErrorText.length > 0 ? "#FECDD3" : "#E4E4E7"
                                font.pixelSize: 12
                                wrapMode: TextEdit.WordWrap
                                readOnly: true
                                selectByMouse: true
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // 3. PRECISION HAIRLINE SEPARATOR (Fixed 1px)
                // ---------------------------------------------------------
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.maximumHeight: 1

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(1, 1, 1, 0.07)
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        height: 1
                        width: (searchInput.activeFocus || noteBodyArea.activeFocus || localMusicInput.activeFocus) ? parent.width : 0
                        color: Qt.rgba(1, 1, 1, 0.28)
                        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }
                }

                // ---------------------------------------------------------
                // 4. BOTTOM SEGMENTED TAB SWITCHER (Fixed 26px)
                // ---------------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    Layout.maximumHeight: 26
                    spacing: 6

                    Rectangle {
                        id: dockTrack
                        readonly property int tabWidth: 58
                        readonly property int tabSpacing: 2
                        Layout.preferredWidth: (tabWidth * root.engines.length) + (tabSpacing * (root.engines.length - 1)) + 6
                        Layout.preferredHeight: 26
                        radius: 9
                        color: Qt.rgba(0, 0, 0, 0.36)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.07)

                        Rectangle {
                            id: activePill
                            y: 3
                            x: 3 + root.currentEngineIndex * (dockTrack.tabWidth + dockTrack.tabSpacing)
                            width: dockTrack.tabWidth
                            height: 20
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.11)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.15)

                            Behavior on x {
                                SpringAnimation {
                                    spring: 5.2
                                    damping: 0.36
                                }
                            }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 3
                            spacing: dockTrack.tabSpacing

                            Repeater {
                                model: root.engines
                                delegate: Item {
                                    width: dockTrack.tabWidth
                                    height: 20

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Rectangle {
                                            width: 4
                                            height: 4
                                            radius: 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: modelData.color
                                            opacity: index === root.currentEngineIndex ? 1.0 : 0.35
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                        }

                                        Text {
                                            text: modelData.short
                                            color: index === root.currentEngineIndex ? "#FAFAFA" : "#71717A"
                                            font.pixelSize: 10
                                            font.weight: index === root.currentEngineIndex ? Font.DemiBold : Font.Normal
                                            Behavior on color { ColorAnimation { duration: 140 } }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.currentEngineIndex = index
                                            if (root.engines[index].name === "Note" && noteBodyArea) {
                                                noteBodyArea.forceActiveFocus()
                                            } else if (root.engines[index].name === "Music") {
                                                if (!root.localMusicLoadedOnce) {
                                                    root.searchLocalMusic("")
                                                }
                                                if (localMusicInput) {
                                                    localMusicInput.forceActiveFocus()
                                                }
                                            } else if (searchInput) {
                                                searchInput.forceActiveFocus()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Row {
                        spacing: 4

                        Rectangle {
                            width: tabCapText.implicitWidth + 8
                            height: 18
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.04)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)

                            Text {
                                id: tabCapText
                                anchors.centerIn: parent
                                text: "Tab"
                                color: "#71717A"
                                font.pixelSize: 9
                                font.weight: Font.Medium
                            }
                        }

                        Rectangle {
                            width: escCapText.implicitWidth + 8
                            height: 18
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.04)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)

                            Text {
                                id: escCapText
                                anchors.centerIn: parent
                                text: "Esc"
                                color: "#71717A"
                                font.pixelSize: 9
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }
}
