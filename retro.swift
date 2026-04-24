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

    var notificationDate: String {
        // Parse "2026-04-23-140000" into "MMMM d, h:mm a" (e.g. April 30, 2:10 PM)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        if let date = formatter.date(from: timestamp) {
            let display = DateFormatter()
            display.dateFormat = "MMMM d, h:mm a"
            return display.string(from: date)
        }
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

func findVersions(for inputPath: String, debugLogger: ((String) -> Void)? = nil) -> [BackupVersion] {
    let fm = FileManager.default
    let targetPath = resolveInputPath(inputPath)
    var versions: [BackupVersion] = []
    var backupPoints: Set<String> = []
    
    // --- Discovery phase ---
    
    // --- Discovery phase ---
    
    // 1. Discover mounted TM drives via destinationinfo (Most common)
    let destInfo = runProcess("/usr/bin/tmutil", args: ["destinationinfo"])
    for line in destInfo.components(separatedBy: .newlines) where line.contains("Mount Point") {
        if let path = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces), !path.isEmpty {
            debugLogger?("Checking TM destination: \(path)")
            // Check root (Modern APFS)
            if let entries = try? fm.contentsOfDirectory(atPath: path) {
                for entry in entries where entry.hasSuffix(".previous") || entry.hasSuffix(".backup") {
                    backupPoints.insert("\(path)/\(entry)")
                }
            }
            // Check Backups.backupdb (Legacy HFS+)
            let dbPath = "\(path)/Backups.backupdb"
            if let computers = try? fm.contentsOfDirectory(atPath: dbPath) {
                for computer in computers {
                    let computerPath = "\(dbPath)/\(computer)"
                    if let entries = try? fm.contentsOfDirectory(atPath: computerPath) {
                        for entry in entries where entry.hasSuffix(".previous") || entry.hasSuffix(".backup") || entry == "Latest" {
                            backupPoints.insert("\(computerPath)/\(entry)")
                        }
                    }
                }
            }
        }
    }
    
    // 2. Local snapshots (already mounted)
    let snapRoot = "/Volumes/com.apple.TimeMachine.localsnapshots/Backups.backupdb"
    if let computers = try? fm.contentsOfDirectory(atPath: snapRoot) {
        for computer in computers {
            let computerPath = "\(snapRoot)/\(computer)"
            if let snaps = try? fm.contentsOfDirectory(atPath: computerPath) {
                for snap in snaps {
                    backupPoints.insert("\(computerPath)/\(snap)")
                }
            }
        }
    }
    
    // 3. tmutil listbackups -m (Mounts and lists EVERY available historical backup)
    let tmutilOutput = runProcess("/usr/bin/tmutil", args: ["listbackups", "-m"])
    for path in tmutilOutput.components(separatedBy: .newlines) where !path.isEmpty {
        backupPoints.insert(path)
    }
    
    // 4. Hidden volumes (Source 3 legacy crawl fallback)
    let tmHidden = "/Volumes/.timemachine"
    if let uuids = try? fm.contentsOfDirectory(atPath: tmHidden) {
        for uuid in uuids {
            let uuidPath = "\(tmHidden)/\(uuid)"
            if let backups = try? fm.contentsOfDirectory(atPath: uuidPath) {
                for backup in backups where backup.hasSuffix(".backup") {
                    backupPoints.insert("\(uuidPath)/\(backup)")
                }
            }
        }
    }
    
    // 5. Hidden localsnapshots discovery via tmutil dates (Backup to mounted ones)
    let snapOutput = runProcess("/usr/bin/tmutil", args: ["listlocalsnapshotdates", "/"])
    for line in snapOutput.components(separatedBy: .newlines) where line.contains("-") {
        let snapshotDate = line.trimmingCharacters(in: .whitespaces)
        if !snapshotDate.isEmpty {
            if let computers = try? fm.contentsOfDirectory(atPath: snapRoot) {
                for computer in computers {
                    backupPoints.insert("\(snapRoot)/\(computer)/\(snapshotDate)")
                }
            }
        }
    }

    debugLogger?("Found \(backupPoints.count) potential backup points. Searching for file...")

    // --- Search phase ---
    
    func checkCandidate(_ path: String, ts: String) -> Bool {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir) {
            var isReal = true
            if !isDir.boolValue {
                if let attr = try? fm.attributesOfItem(atPath: path), let size = attr[.size] as? NSNumber, size.intValue == 0 {
                    isReal = false // Filter out 0-byte stubs
                }
            }
            if isReal {
                versions.append(BackupVersion(sourcePath: path, originalPath: inputPath, timestamp: ts))
                return true
            }
        }
        return false
    }

    for point in backupPoints {
        let ts = URL(fileURLWithPath: point).lastPathComponent
            .replacingOccurrences(of: ".previous", with: "")
            .replacingOccurrences(of: ".backup", with: "")
        
        // 1. Check common volume roots inside the point (Data, Macintosh HD, etc.)
        if let contents = try? fm.contentsOfDirectory(atPath: point) {
            for volumeRoot in contents {
                let volumePath = "\(point)/\(volumeRoot)"
                if checkCandidate("\(volumePath)/Data\(targetPath)", ts: ts) { continue }
                if checkCandidate("\(volumePath)\(targetPath)", ts: ts) { continue }
            }
        }
        
        // 2. Check point itself (Direct mounts)
        if checkCandidate("\(point)/Data\(targetPath)", ts: ts) { continue }
        if checkCandidate("\(point)\(targetPath)", ts: ts) { continue }
        
        // 3. Nested .backup (Network backups)
        let nestedBackup = "\(point)/\(ts).backup"
        if checkCandidate("\(nestedBackup)/Data\(targetPath)", ts: ts) { continue }
        if checkCandidate("\(nestedBackup)\(targetPath)", ts: ts) { continue }
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
            : "Alfred needs Full Disk Access"
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
        let sourceLabel = v.isLocalSnapshot ? "Local Snapshot" : "External Drive"
        items.append([
            "title": v.humanReadable,
            "subtitle": "\(v.ageDescription)  ·  \(sourceLabel)",
            "arg": v.sourcePath,           // The full backup source path
            "type": "file",
            "valid": true,
            "variables": [
                "SOURCE_PATH": v.sourcePath,
                "DEST_PATH": originalPath,
                "FILE_NAME": URL(fileURLWithPath: originalPath).lastPathComponent,
                "VERSION_DATE": v.notificationDate
            ],
            "icon": ["type": "fileicon", "path": originalPath],
            "mods": [
                "cmd": [
                    "subtitle": "⌘ Restore to Home folder instead",
                    "valid": true,
                    "variables": ["RESTORE_TO_HOME": "1"]
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
func restore(sourcePath: String, destPath: String, toHome: Bool = false) {
    let fm = FileManager.default
    
    // Helper to perform the copy
    func attemptCopy(to finalDest: String) throws {
        if fm.fileExists(atPath: finalDest) {
            try fm.removeItem(atPath: finalDest)
        }
        
        do {
            try fm.copyItem(atPath: sourcePath, toPath: finalDest)
        } catch {
            // Clean up any empty/broken folder left by FileManager before falling back
            if fm.fileExists(atPath: finalDest) {
                try? fm.removeItem(atPath: finalDest)
            }
            
            // Standard copy fails on external TM backups due to strict ACLs/xattrs.
            // Fallback to ditto, which is robust for Mac app bundles and TM paths
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            task.arguments = [sourcePath, finalDest]
            try? task.run()
            task.waitUntilExit()
            
            // ditto may return non-zero for ACL failures even if copy succeeds.
            if !fm.fileExists(atPath: finalDest) || task.terminationStatus != 0 {
                // If ditto fails, ensure path is clean again before trying cp
                if fm.fileExists(atPath: finalDest) {
                    try? fm.removeItem(atPath: finalDest)
                }
                
                // Fallback to standard cp -R
                let task2 = Process()
                task2.executableURL = URL(fileURLWithPath: "/bin/cp")
                task2.arguments = ["-a", sourcePath, finalDest]
                try? task2.run()
                task2.waitUntilExit()
                
                // cp -R often returns 1 on macOS for xattr/ACL failures even if the copy succeeds.
                // We check if the destination exists as our ultimate success metric.
                if !fm.fileExists(atPath: finalDest) {
                    throw error // throw the original FileManager error
                }
            }
        }
    }
    
    let destURL = URL(fileURLWithPath: destPath)
    let ext = destURL.pathExtension
    let base = destURL.deletingPathExtension().lastPathComponent
    let restoredName = ext.isEmpty ? "\(base) (Restored)" : "\(base) (Restored).\(ext)"
    
    let homeDest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(restoredName).path
    let originalDest = destURL.deletingLastPathComponent().appendingPathComponent(restoredName).path
    
    func finalizeRestore(at path: String) {
        // 1. Remove ACLs that might block attribute modifications
        _ = runProcess("/bin/chmod", args: ["-R", "-N", path])
        // 2. Remove immutable flags
        _ = runProcess("/usr/bin/chflags", args: ["-R", "nouchg", path])
        // 3. Ensure user has read/write permissions to modify attributes
        _ = runProcess("/bin/chmod", args: ["-R", "u+rw", path])
        // 4. Remove all extended attributes (including quarantine)
        _ = runProcess("/usr/bin/xattr", args: ["-rc", path])
        // 5. Ad-hoc sign if it's an app bundle to fix any broken signatures from copying
        if path.hasSuffix(".app") {
            _ = runProcess("/usr/bin/codesign", args: ["--force", "--deep", "--sign", "-", path])
        }
    }

    if toHome {
        do {
            try attemptCopy(to: homeDest)
            finalizeRestore(at: homeDest)
            print("Successfully restored to Home folder as \(restoredName)")
        } catch {
            print("Restore failed: \(error.localizedDescription)")
            exit(1)
        }
    } else {
        do {
            // Try original location first
            try attemptCopy(to: originalDest)
            finalizeRestore(at: originalDest)
            print("Successfully restored to \(URL(fileURLWithPath: originalDest).lastPathComponent)")
        } catch {
            // Fallback to home folder if permission denied or other error
            do {
                try attemptCopy(to: homeDest)
                finalizeRestore(at: homeDest)
                print("Restored to Home folder (original folder is read-only or permission denied)")
            } catch let fallbackError {
                print("Restore failed entirely: \(fallbackError.localizedDescription)")
                exit(1)
            }
        }
    }
}

// MARK: - Main CLI Dispatch
let args = CommandLine.arguments
guard args.count > 1 else {
    print("Usage: alfred-tm list <path> [--alfred]")
    print("       alfred-tm restore <source_path> <dest_path> [--desktop]")
    exit(1)
}

switch args[1] {
case "list":
    guard args.count > 2 else {
        fputs("Error: alfred-tm list requires a file path\n", stderr)
        exit(1)
    }
    let isAlfred = args.contains("--alfred")
    
    // Mount local snapshots to ensure they are accessible
    _ = runProcess("/usr/bin/tmutil", args: ["mountlocalsnapshots", "/"])
    
    let versions = findVersions(for: args[2]) { msg in
        if !isAlfred {
            fputs("DEBUG: \(msg)\n", stderr)
        }
    }
    
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
        fputs("Error: alfred-tm restore requires source and destination paths\n", stderr)
        exit(1)
    }
    let sourcePath = args[2]
    let destPath = args[3]
    let toHome = args.contains("--home")
    restore(sourcePath: sourcePath, destPath: destPath, toHome: toHome)

default:
    fputs("Unknown command: \(args[1])\n", stderr)
    exit(1)
}
