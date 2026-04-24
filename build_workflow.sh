#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Compiling retro binary..."
swiftc retro.swift -o retro 2>&1
echo "✅ Compiled successfully"

echo "📦 Building Alfred workflow bundle..."
BUNDLE_DIR="$SCRIPT_DIR/RetroWorkflow.bundle"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# Copy binary into bundle
cp retro "$BUNDLE_DIR/retro"

# Write the info.plist using Python for reliable plist generation
python3 - "$BUNDLE_DIR" << 'PYEOF'
import sys
import plistlib
import uuid

bundle_dir = sys.argv[1]

# UIDs for our workflow nodes
UID_UA       = "A1B2C3D4-0001-0001-0001-000000000001"
UID_FILTER   = "A1B2C3D4-0002-0002-0002-000000000002"
UID_RESTORE  = "A1B2C3D4-0003-0003-0003-000000000003"
UID_OPENURL  = "A1B2C3D4-0005-0005-0005-000000000005"

workflow = {
    "bundleid": "com.saihgupr.retro",
    "category": "Productivity",
    "createdby": "saihgupr",
    "description": "Browse and restore files from Time Machine backups — no slow UI required.",
    "disabled": False,
    "name": "Retro — Time Machine Restore",
    "version": "1.1.0",
    "webaddress": "",
    "readme": """## Retro — Time Machine Restore

Select any file or application in Finder or Alfred, press your Universal Actions hotkey, and choose **"Retro: Browse Time Machine Versions"**.

You'll see a list of all available backup versions with human-readable dates.

**↩ Enter** — Restores a `.restored` copy next to the original  
**⌘↩ Enter** — Restores a copy to your Desktop instead

Once happy, rename/replace the original with the `.restored` copy.""",

    "connections": {
        # UA → Script Filter
        UID_UA: [
            {
                "destinationuid": UID_FILTER,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": False,
            }
        ],
        # Script Filter → Restore (Enter key)
        UID_FILTER: [
            {
                "destinationuid": UID_RESTORE,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": True,
            }
        ],
        UID_RESTORE: [],
        UID_OPENURL: [],
    },

    "objects": [
        # ─── 1. Universal Action Trigger ─────────────────────────────────────────
        {
            "type": "alfred.workflow.trigger.universalaction",
            "uid": UID_UA,
            "version": 1,
            "config": {
                "acceptsfiles": True,
                "acceptstext": False,
                "acceptsurls": False,
                "acceptsmulti": 0,
                "name": "Retro: Browse Time Machine Versions",
            },
        },

        # ─── 2. Script Filter ────────────────────────────────────────────────────
        # This is triggered by the Universal Action; {query} = the selected file path
        {
            "type": "alfred.workflow.input.scriptfilter",
            "uid": UID_FILTER,
            "version": 3,
            "config": {
                "alfredfiltersresults": False,
                "alfredfiltersresultsmatchmode": 0,
                "argumenttreatemptyqueryasnil": True,
                "argumenttrimmode": 0,
                "argumenttype": 1,    # 1 = pass argument as {query}
                "escaping": 102,
                "keyword": "",
                "queuedelaycustom": 3,
                "queuedelayimmediatelyinitially": True,
                "queuedelaymode": 0,
                "queuemode": 1,
                "runningsubtext": "Scanning Time Machine backups…",
                "script": 'chmod +x ./retro 2>/dev/null; ./retro list "$1" --alfred',
                "scriptargtype": 1,
                "scriptfile": "",
                "subtext": "Pick a backup version to restore",
                "title": "Time Machine Versions",
                "type": 5,  # 5 = /bin/zsh
                "withspace": True,
            },
        },

        # ─── 3. Run Script (Restore or open System Settings) ────────────────────
        # SOURCE_PATH and DEST_PATH come from Alfred variables set per-item in the JSON.
        # If the arg is a URL (FDA error case), it opens System Settings instead.
        {
            "type": "alfred.workflow.action.script",
            "uid": UID_RESTORE,
            "version": 2,
            "config": {
                "concurrently": False,
                "escaping": 0,
                "script": (
                    "#!/bin/zsh\n"
                    "# If arg is a URL (FDA error case), open it\n"
                    'ARG="$1"\n'
                    'if [[ "$ARG" == open* ]]; then\n'
                    '    /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"\n'
                    '    exit 0\n'
                    'fi\n'
                    "\n"
                    'chmod +x ./retro 2>/dev/null\n'
                    'SOURCE="{var:SOURCE_PATH}"\n'
                    'DEST="{var:DEST_PATH}"\n'
                    'DESKTOP="{var:RESTORE_TO_DESKTOP}"\n'
                    "\n"
                    'if [[ "$DESKTOP" == "1" ]]; then\n'
                    '    ./retro restore "$SOURCE" "$DEST" --desktop\n'
                    "else\n"
                    '    ./retro restore "$SOURCE" "$DEST"\n'
                    "fi\n"
                ),
                "scriptargtype": 1,
                "scriptfile": "",
                "type": 5,  # /bin/zsh
            },
        },
    ],

    "uidata": {
        UID_UA:      {"note": "Universal Action trigger", "xpos": 60.0,  "ypos": 100.0},
        UID_FILTER:  {"note": "Script Filter: list versions", "xpos": 340.0, "ypos": 100.0},
        UID_RESTORE: {"note": "Run Script: restore file or open FDA settings", "xpos": 620.0, "ypos": 100.0},
    },
}

out_path = f"{bundle_dir}/info.plist"
with open(out_path, "wb") as f:
    plistlib.dump(workflow, f, fmt=plistlib.FMT_XML, sort_keys=False)

print(f"✅ info.plist written to {out_path}")
PYEOF

# Verify plist is valid
plutil -lint "$BUNDLE_DIR/info.plist" && echo "✅ plist is valid"

# Package as .alfredworkflow
OUTPUT="$SCRIPT_DIR/Retro.alfredworkflow"
rm -f "$OUTPUT"
cd "$BUNDLE_DIR"
zip -r "$OUTPUT" . -x "*.DS_Store"
cd "$SCRIPT_DIR"
rm -rf "$BUNDLE_DIR"

echo ""
echo "🎉 Done! Retro.alfredworkflow created at:"
echo "   $OUTPUT"
echo ""
echo "To install: double-click Retro.alfredworkflow"
echo ""
echo "Usage:"
echo "  1. In Finder, click any file or app"
echo "  2. Press your Alfred Universal Actions hotkey"  
echo "  3. Select 'Retro: Browse Time Machine Versions'"
echo "  4. Choose a date and press Enter to restore"
