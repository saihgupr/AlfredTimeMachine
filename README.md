# Retro 🕰️

Retro is a high-speed CLI tool for restoring files from macOS Time Machine backups and APFS snapshots without using the official GUI.

## Usage

### 1. List available versions
```bash
./retro list <file_path>
```
Example: `./retro list ~/Documents/report.pdf`

### 2. Restore a specific version
```bash
./retro restore <file_path> --index <n>
```
This will create a new file at `<file_path>.restored`.

## Installation

Move the `retro` binary to a folder in your PATH (e.g., `/usr/local/bin`):
```bash
sudo mv retro /usr/local/bin/
```

## How it works
Retro scans:
- Mounted Time Machine volumes (`/Volumes/TimeMachine`)
- Local APFS snapshots (`/Volumes/com.apple.TimeMachine.localsnapshots`)
- Hidden Time Machine mounts (`/Volumes/.timemachine`)

It maps your file path to the internal structure of these backups (handling the `Data/` or `Macintosh HD/` root shifts automatically).
