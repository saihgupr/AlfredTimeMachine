# Retro — Time Machine Restore for Alfred

> Instant file & app restoration from Time Machine backups, right from Alfred. No slow UI, no spinning stars.

## How it Works

**Retro** is a two-part tool:

1. **`retro` binary** — A compiled Swift CLI that scans your Time Machine backups (both external drive and local APFS snapshots) and finds all historical versions of any file or folder.
2. **`Retro.alfredworkflow`** — An Alfred 5 workflow that wraps the binary with a clean, fast picker UI.

## Installation

### 1. Install the Alfred Workflow

Double-click `Retro.alfredworkflow` to import it into Alfred. Alfred will ask you to confirm — click **Import**.

> **Alfred Powerpack required.** Universal Actions need Alfred's Powerpack license.

### 2. (Optional) Rebuild from Source

If you update `retro.swift`, rebuild and repackage with:

```bash
bash build_workflow.sh
```

This recompiles the binary and creates a fresh `Retro.alfredworkflow`.

---

## Usage

### Via Universal Actions (Recommended)

1. In **Finder**, click any file or application to select it
2. Press your **Alfred Universal Actions hotkey** (default: `⌥→`)
3. Type **"retro"** or scroll to find **"Retro: Browse Time Machine Versions"**
4. Alfred shows all backup versions with human-readable dates:
   - **"Thu Apr 23 · 7:00 AM"** — *Yesterday · 💾 External Drive*
   - **"Thu Apr 23 · 2:00 PM"** — *20 hours ago · 📍 Local Snapshot*
5. Press **↩ Enter** to restore

### Keyboard Shortcuts in the Version Picker

| Key | Action |
|-----|--------|
| `↩ Enter` | Restore as `filename.restored` next to the original |
| `⌘↩ Enter` | Restore a copy to your Desktop instead |

### Via Terminal (CLI)

```bash
# List all backup versions for a file
./retro list /Applications/Dia.app
./retro list ~/.zshrc

# List versions in Alfred JSON format
./retro list /Applications/Dia.app --alfred

# Restore: creates a .restored copy next to the original  
./retro restore "/path/to/backup/source" "/Applications/Dia.app"

# Restore to Desktop instead
./retro restore "/path/to/backup/source" "/Applications/Dia.app" --desktop
```

---

## What Gets Scanned

Retro checks three sources, newest first:

| Source | Path | Notes |
|--------|------|-------|
| External TM Drive | `/Volumes/TimeMachine/` | Hourly backups on attached drive |
| Local Snapshots | `/Volumes/com.apple.TimeMachine.localsnapshots/` | Last ~24h, stored on your internal drive |
| Hidden TM Volume | `/Volumes/.timemachine/` | Alternate external drive mount path |

---

## After Restoring

Retro creates a **`.restored`** copy (never overwrites your current file). Once you've verified the restored version:

**For files:**
```bash
# Swap the restored file into place
mv ~/Documents/Report.pdf ~/Documents/Report.pdf.bad
mv ~/Documents/Report.pdf.restored ~/Documents/Report.pdf
```

**For apps:**
```bash
# Move old version away, put restored version in its place
mv /Applications/Dia.app /Applications/Dia.app.bad
mv /Applications/Dia.app.restored /Applications/Dia.app
```

---

## Building

Requirements: macOS 12+, Xcode Command Line Tools, Alfred 5 with Powerpack

```bash
# Build everything
bash build_workflow.sh
```

This:
1. Compiles `retro.swift` → `retro` binary
2. Generates a valid Alfred 5 `info.plist` using Python
3. Packages `retro` + `info.plist` → `Retro.alfredworkflow`
