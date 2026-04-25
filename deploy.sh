#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Compiling binary..."
swiftc retro.swift -o alfred-tm 2>&1
echo "Compiled successfully"

echo "Building Alfred workflow bundle..."
BUNDLE_DIR="$SCRIPT_DIR/AlfredTimeMachine.bundle"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# Copy binary and icon into bundle
cp alfred-tm "$BUNDLE_DIR/alfred-tm"
cp icon.png "$BUNDLE_DIR/icon.png"

# Write the info.plist using Python for reliable plist generation
python3 - "$BUNDLE_DIR" << 'PYEOF'
import sys
import plistlib
import uuid

bundle_dir = sys.argv[1]

# UIDs for our workflow nodes
UID_UA       = "A1B2C3D4-0001-0001-0001-000000000001"
UID_VARS     = "A1B2C3D4-0004-0004-0004-000000000004"
UID_FILTER   = "A1B2C3D4-0002-0002-0002-000000000002"
UID_RESTORE  = "A1B2C3D4-0003-0003-0003-000000000003"
UID_NOTIFY_S = "A1B2C3D4-0005-0005-0005-000000000005"
UID_NOTIFY_F = "A1B2C3D4-0006-0006-0006-000000000006"
UID_HIDE     = "A1B2C3D4-0007-0007-0007-000000000007"
UID_SEARCH   = "A1B2C3D4-0008-0008-0008-000000000008"
UID_SEARCH_V = "A1B2C3D4-0009-0009-0009-000000000009"

workflow = {
    "bundleid": "com.saihgupr.alfred-time-machine",
    "category": "Productivity",
    "createdby": "saihgupr",
    "description": "Browse and restore files from Time Machine backups — no slow UI required.",
    "disabled": False,
    "name": "Alfred Time Machine",
    "version": "1.1.0",
    "webaddress": "",
    "readme": """## Alfred Time Machine

Select any file or application in Finder or Alfred, press your Universal Actions hotkey, and choose **"Alfred Time Machine"**.

You'll see a list of all available backup versions with human-readable dates.

**↩ Enter** — Restores a `(Restored)` copy next to the original  
**⌘↩ Enter** — Restores a copy to your Home folder instead

Once happy, rename/replace the original with the `(Restored)` copy.""",

    "connections": {
        # UA → Args & Vars
        UID_UA: [
            {
                "destinationuid": UID_VARS,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": False,
            }
        ],
        # Args & Vars → Script Filter
        UID_VARS: [
            {
                "destinationuid": UID_FILTER,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": False,
            }
        ],
        # Script Filter → Hide Alfred, Start Notification, and Restore Action
        UID_FILTER: [
            {
                "destinationuid": UID_HIDE,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": True,
            },
            {
                "destinationuid": UID_NOTIFY_S,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": True,
            },
            {
                "destinationuid": UID_RESTORE,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": True,
            }
        ],
        # Restore → Finished Notification
        UID_RESTORE: [
            {
                "destinationuid": UID_NOTIFY_F,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": False,
            }
        ],
        UID_NOTIFY_S: [],
        UID_NOTIFY_F: [],
        UID_HIDE: [],
        # Keyword Search → Set Vars
        UID_SEARCH: [
            {
                "destinationuid": UID_SEARCH_V,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": False,
            }
        ],
        # Set Vars → List Versions
        UID_SEARCH_V: [
            {
                "destinationuid": UID_FILTER,
                "modifiers": 0,
                "modifiersubtext": "",
                "vitoclose": False,
            }
        ],
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
                "name": "Alfred Time Machine",
            },
        },
        
        # ─── 2. Args and Vars ────────────────────────────────────────────────────
        {
            "type": "alfred.workflow.utility.argument",
            "uid": UID_VARS,
            "version": 1,
            "config": {
                "argument": "",
                "passthroughargument": False,
                "variables": {
                    "TARGET_FILE": "{query}",
                }
            },
        },

        # ─── 3. Script Filter ────────────────────────────────────────────────────
        {
            "type": "alfred.workflow.input.scriptfilter",
            "uid": UID_FILTER,
            "version": 3,
            "config": {
                "alfredfiltersresults": True,
                "alfredfiltersresultsmatchmode": 0,
                "argumenttreatemptyqueryasnil": True,
                "argumenttrimmode": 0,
                "argumenttype": 1,
                "escaping": 102,
                "keyword": "",
                "queuedelaycustom": 3,
                "queuedelayimmediatelyinitially": True,
                "queuedelaymode": 0,
                "queuemode": 1,
                "runningsubtext": "Scanning Time Machine backups…",
                "script": 'chmod +x ./alfred-tm 2>/dev/null; ./alfred-tm list "$TARGET_FILE" --alfred',
                "scriptargtype": 1,
                "scriptfile": "",
                "subtext": "Pick a backup version to restore",
                "title": "Time Machine Versions",
                "type": 5,
                "withspace": True,
            },
        },

        # ─── 4. Run Script (Restore) ─────────────────────────────────────────────
        {
            "type": "alfred.workflow.action.script",
            "uid": UID_RESTORE,
            "version": 2,
            "config": {
                "concurrently": False,
                "escaping": 0,
                "script": (
                    "#!/bin/zsh\n"
                    'ARG="$1"\n'
                    'if [[ "$ARG" == open* ]]; then\n'
                    '    /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"\n'
                    '    exit 0\n'
                    'fi\n'
                    "\n"
                    'chmod +x ./alfred-tm 2>/dev/null\n'
                    'SOURCE="$SOURCE_PATH"\n'
                    'DEST="$DEST_PATH"\n'
                    'DESKTOP="$RESTORE_TO_HOME"\n'
                    "\n"
                    'if [[ "$DESKTOP" == "1" ]]; then\n'
                    '    ./alfred-tm restore "$SOURCE" "$DEST" --home\n'
                    "else\n"
                    '    ./alfred-tm restore "$SOURCE" "$DEST"\n'
                    "fi\n"
                ),
                "scriptargtype": 1,
                "scriptfile": "",
                "type": 5,
            },
        },
        
        # ─── 5. Notification: Started ───────────────────────────────────────────
        {
            "type": "alfred.workflow.output.notification",
            "uid": UID_NOTIFY_S,
            "version": 1,
            "config": {
                "title": "Alfred Time Machine",
                "text": "Restoring {var:FILE_NAME}\n{var:VERSION_DATE}",
            },
        },

        # ─── 6. Notification: Finished ──────────────────────────────────────────
        {
            "type": "alfred.workflow.output.notification",
            "uid": UID_NOTIFY_F,
            "version": 1,
            "config": {
                "title": "Alfred Time Machine",
                "text": "{var:FILE_NAME} Finished Restoring!",
            },
        },

        # ─── 7. Hide Alfred Utility ──────────────────────────────────────────────
        {
            "type": "alfred.workflow.utility.hidealfred",
            "uid": UID_HIDE,
            "version": 1,
            "config": {},
        },

        # ─── 8. Script Filter (Search Local) ─────────────────────────────────────
        {
            "type": "alfred.workflow.input.scriptfilter",
            "uid": UID_SEARCH,
            "version": 3,
            "config": {
                "alfredfiltersresults": False,
                "alfredfiltersresultsmatchmode": 0,
                "argumenttreatemptyqueryasnil": True,
                "argumenttrimmode": 0,
                "argumenttype": 1,
                "escaping": 102,
                "keyword": "atm",
                "queuedelaycustom": 3,
                "queuedelayimmediatelyinitially": True,
                "queuedelaymode": 0,
                "queuemode": 1,
                "runningsubtext": "Searching local files…",
                "script": 'chmod +x ./alfred-tm 2>/dev/null; ./alfred-tm search-local "$1"',
                "scriptargtype": 1,
                "scriptfile": "",
                "subtext": "Type a file name to find versions for…",
                "title": "Alfred Time Machine",
                "type": 5,
                "withspace": False,
            },
        },

        # ─── 9. Args and Vars (Search selection) ──────────────────────────────────
        {
            "type": "alfred.workflow.utility.argument",
            "uid": UID_SEARCH_V,
            "version": 1,
            "config": {
                "argument": "",
                "passthroughargument": False,
                "variables": {
                    "TARGET_FILE": "{query}",
                }
            },
        },
    ],

    "uidata": {
        UID_UA:       {"note": "Universal Action trigger", "xpos": 60.0,  "ypos": 100.0},
        UID_VARS:     {"note": "Save TARGET_FILE", "xpos": 230.0, "ypos": 130.0},
        UID_FILTER:   {"note": "List versions", "xpos": 340.0, "ypos": 100.0},
        UID_RESTORE:  {"note": "Restore file", "xpos": 520.0, "ypos": 150.0},
        UID_NOTIFY_S: {"note": "Started Notify", "xpos": 520.0, "ypos": 30.0},
        UID_NOTIFY_F: {"note": "Finished Notify", "xpos": 700.0, "ypos": 150.0},
        UID_SEARCH:   {"note": "Keyword Search", "xpos": 60.0,  "ypos": 300.0},
        UID_SEARCH_V: {"note": "Set Selection", "xpos": 230.0, "ypos": 330.0},
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
OUTPUT="$SCRIPT_DIR/AlfredTimeMachine.alfredworkflow"
rm -f "$OUTPUT"
cd "$BUNDLE_DIR"
zip -r "$OUTPUT" . -x "*.DS_Store"
cd "$SCRIPT_DIR"
rm -rf "$BUNDLE_DIR"

echo ""
echo "Done! AlfredTimeMachine.alfredworkflow created at:"
echo "   $OUTPUT"
echo ""
echo "To install: double-click AlfredTimeMachine.alfredworkflow"
echo ""
echo "Usage:"
echo "  1. In Finder, click any file or app"
echo "  2. Press your Alfred Universal Actions hotkey"  
echo "  3. Select 'Alfred Time Machine'"
echo "  4. Choose a date and press Enter to restore"

# Automatically open and install in Alfred
open "$OUTPUT"
