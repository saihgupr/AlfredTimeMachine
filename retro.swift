import Foundation

// MARK: - Data Model
struct BackupVersion {
    let sourcePath: String  // Full path inside backup
    let originalPath: String  // Original file/folder path
    let timestamp: String   // e.g. "2026-04-23-140000"
    
    var humanReadable: String {
        // Parse "2026-04-23-140000" into "Thu Apr 23 · 2:00 PM"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        if let date = formatter.date(from: timestamp) {
            let display = DateFormatter()
            display.dateFormat = "EEE MMM d · h:mm a"
            return display.string(from: date)
        }
        // Fallback: just clean up the string
        return timestamp
    }
    
    var ageDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        guard let date = formatter.date(from: timestamp) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "Just now" }
        if interval < 7200 { return "1 hour ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours ago" }
        if interval < 172800 { return "Yesterday" }
        return "\(Int(interval / 86400)) days ago"
    }
    
    var isLocalSnapshot: Bool {
        return sourcePath.contains("TimeMachine.localsnapshots")
    }
}

// MARK: - Helpers
func runProcess(_ exec: String, args: [String]) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: exec)
    task.arguments = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe() // discard stderr
    try? task.run()
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

// MARK: - Full Disk Access Check
// Returns true if we can read Time Machine paths (proxy for FDA).
func hasFullDiskAccess() -> Bool {
    let fm = FileManager.default
    // These paths require FDA on macOS 10.15+
    let testPaths = [
        "/Volumes/com.apple.TimeMachine.localsnapshots",
        "/Volumes/TimeMachine",
        "/Volumes/.timemachine"
    ]
    // If at least one TM path is accessible, we have enough access
    for path in testPaths {
        if fm.fileExists(atPath: path) {
            return true
        }
    }
    return false
}

// MARK: - Backup Discovery
// NOTE: We do NOT call `tmutil mountlocalsnapshots` — it requires root/admin
// and will silently fail when run from Alfred. Instead we rely on:
//   a) Snapshots already mounted at the known path
//   b) `tmutil listlocalsnapshots` (no root needed) to enumerate snapshot IDs

func resolveInputPath(_ rawPath: String) -> String {
    var path = URL(fileURLWithPath: rawPath).standardized.path
    // Alfred passes firmlink path for apps; TM stores under Data without the prefix
    if path.hasPrefix("/System/Volumes/Data") {
        path = String(path.dropFirst("/System/Volumes/Data".count))
    }
    return path
}

func findVersions(for inputPath: String) -> [BackupVersion] {
    let fm = FileManager.default
    let targetPath = resolveInputPath(inputPath)
    var versions: [BackupVersion] = []
    
    // --- Source 1: External TM drive at /Volumes/TimeMachine ---
    let tmRoot = "/Volumes/TimeMachine"
    if let entries = try? fm.contentsOfDirectory(atPath: tmRoot) {
        for entry in entries {
            let entryPath = "\(tmRoot)/\(entry)"
            let ts = entry
                .replacingOccurrences(of: ".previous", with: "")
                .replacingOccurrences(of: ".backup", with: "")
            
            if let subDirs = try? fm.contentsOfDirectory(atPath: entryPath) {
                for sub in subDirs {
                    let candidate = "\(entryPath)/\(sub)\(targetPath)"
                    if fm.fileExists(atPath: candidate) {
                        versions.append(BackupVersion(sourcePath: candidate, originalPath: inputPath, timestamp: ts))
                    }
                }
            }
        }
    }
    
    // --- Source 2: Local snapshots (already mounted by mountlocalsnapshots) ---
    let snapRoot = "/Volumes/com.apple.TimeMachine.localsnapshots/Backups.backupdb"
    if let computers = try? fm.contentsOfDirectory(atPath: snapRoot) {
        for computer in computers {
            let computerPath = "\(snapRoot)/\(computer)"
            if let snaps = try? fm.contentsOfDirectory(atPath: computerPath) {
                for snap in snaps {
                    let candidate = "\(computerPath)/\(snap)/Data\(targetPath)"
                    if fm.fileExists(atPath: candidate) {
                        versions.append(BackupVersion(sourcePath: candidate, originalPath: inputPath, timestamp: snap))
                    }
                }
            }
        }
    }
    
    // --- Source 3: Hidden TM volume at /Volumes/.timemachine ---
    let tmHidden = "/Volumes/.timemachine"
    if let uuids = try? fm.contentsOfDirectory(atPath: tmHidden) {
        for uuid in uuids {
            let uuidPath = "\(tmHidden)/\(uuid)"
            if let backups = try? fm.contentsOfDirectory(atPath: uuidPath) {
                for backup in backups where backup.hasSuffix(".backup") {
                    let backupPath = "\(uuidPath)/\(backup)"
                    let ts = backup.replacingOccurrences(of: ".backup", with: "")
                    if let subDirs = try? fm.contentsOfDirectory(atPath: backupPath) {
                        for sub in subDirs {
                            let candidate = "\(backupPath)/\(sub)\(targetPath)"
                            if fm.fileExists(atPath: candidate) {
                                versions.append(BackupVersion(sourcePath: candidate, originalPath: inputPath, timestamp: ts))
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Deduplicate and sort newest first
    var seen = Set<String>()
    let unique = versions.filter { seen.insert($0.timestamp + $0.sourcePath).inserted }
    return unique.sorted { $0.timestamp > $1.timestamp }
}

// MARK: - Output
func outputAlfredJSON(versions: [BackupVersion], originalPath: String) {
    if versions.isEmpty {
        // Check if the issue is FDA vs genuinely no backups
        let hasFDA = hasFullDiskAccess()
        let title = hasFDA
            ? "No backup versions found"
            : "⚠️ Alfred needs Full Disk Access"
        let subtitle = hasFDA
            ? "Time Machine has no backups for this file"
            : "Open System Settings → Privacy → Full Disk Access → enable Alfred"
        let arg = hasFDA ? "" : "open x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        
        let noResults: [String: Any] = [
            "items": [[
                "title": title,
                "subtitle": subtitle,
                "valid": !hasFDA,  // allow pressing Enter to open System Settings if FDA issue
                "arg": arg,
                "icon": ["path": hasFDA
                    ? "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"
                    : "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarCustomizeIcon.icns"
                ]
            ]]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: noResults),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        return
    }
    
    var items: [[String: Any]] = []
    for v in versions {
        let sourceLabel = v.isLocalSnapshot ? "📍 Local Snapshot" : "💾 External Drive"
        items.append([
            "title": v.humanReadable,
            "subtitle": "\(v.ageDescription)  ·  \(sourceLabel)",
            "arg": v.sourcePath,           // The full backup source path
            "variables": [
                "SOURCE_PATH": v.sourcePath,
                "DEST_PATH": originalPath
            ],
            "icon": ["type": "fileicon", "path": originalPath],
            "mods": [
                "cmd": [
                    "subtitle": "⌘ Restore to Desktop instead",
                    "valid": true,
                    "variables": ["RESTORE_TO_DESKTOP": "1"]
                ]
            ]
        ])
    }
    
    let output: [String: Any] = ["items": items]
    if let data = try? JSONSerialization.data(withJSONObject: output),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

// MARK: - Restore
func restore(sourcePath: String, destPath: String, toDesktop: Bool = false) {
    let fm = FileManager.default
    var finalDest: String
    
    if toDesktop {
        let fileName = URL(fileURLWithPath: destPath).lastPathComponent
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/\(fileName).restored")
        finalDest = desktopURL.path
    } else {
        finalDest = destPath + ".restored"
    }
    
    // Remove any existing .restored
    if fm.fileExists(atPath: finalDest) {
        try? fm.removeItem(atPath: finalDest)
    }
    
    do {
        try fm.copyItem(atPath: sourcePath, toPath: finalDest)
        // Output a notification-friendly message for Alfred
        print("✅ Restored to: \(finalDest)")
    } catch {
        fputs("❌ Restore failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// MARK: - Main CLI Dispatch
let args = CommandLine.arguments
guard args.count > 1 else {
    print("Usage: retro list <path> [--alfred]")
    print("       retro restore <source_path> <dest_path> [--desktop]")
    exit(1)
}

switch args[1] {
case "list":
    guard args.count > 2 else {
        fputs("Error: retro list requires a file path\n", stderr)
        exit(1)
    }
    let isAlfred = args.contains("--alfred")
    let versions = findVersions(for: args[2])
    
    if isAlfred {
        outputAlfredJSON(versions: versions, originalPath: args[2])
    } else {
        if versions.isEmpty {
            print("No backup versions found for: \(args[2])")
        } else {
            print("Backup versions for: \(args[2])\n")
            for (i, v) in versions.enumerated() {
                let source = v.isLocalSnapshot ? "[local]" : "[drive]"
                print("[\(i)] \(v.humanReadable) \(source)")
                print("     \(v.sourcePath)")
            }
        }
    }
    
case "restore":
    guard args.count > 3 else {
        fputs("Error: retro restore requires source and destination paths\n", stderr)
        exit(1)
    }
    let sourcePath = args[2]
    let destPath = args[3]
    let toDesktop = args.contains("--desktop")
    restore(sourcePath: sourcePath, destPath: destPath, toDesktop: toDesktop)

default:
    fputs("Unknown command: \(args[1])\n", stderr)
    exit(1)
}
