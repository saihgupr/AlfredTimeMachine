import Foundation

let fm = FileManager.default
let arguments = CommandLine.arguments

guard arguments.count > 1 else {
    print("Usage:")
    print("  retro list <file_path>")
    print("  retro restore <file_path> --index <n>")
    exit(1)
}

let command = arguments[1]

struct Version {
    let path: String
    let timestamp: String
}

func getBackupPoints() -> [String] {
    var points: [String] = []
    
    // 1. Check /Volumes/TimeMachine
    let tmRoot = "/Volumes/TimeMachine"
    if let contents = try? fm.contentsOfDirectory(atPath: tmRoot) {
        for item in contents {
            if item.hasSuffix(".previous") || item.hasSuffix(".backup") {
                points.append("\(tmRoot)/\(item)")
            }
        }
    }
    
    // 2. Check local snapshots (including unmounted ones)
    // First, try to mount all available local snapshots to make them accessible
    let mountTask = Process()
    mountTask.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
    mountTask.arguments = ["mountlocalsnapshots", "/"]
    try? mountTask.run()
    mountTask.waitUntilExit()

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
    task.arguments = ["listlocalsnapshots", "/"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            // Lines look like: com.apple.TimeMachine.2026-04-23-074039.local
            if line.contains("com.apple.TimeMachine") {
                let parts = line.components(separatedBy: ".")
                if parts.count >= 4 {
                    let timestamp = parts[3]
                    // We assume it's mounted or can be accessed via /Volumes/com.apple.TimeMachine.localsnapshots/...
                    // If not mounted, we'll note it as a snapshot name
                    points.append("SNAPSHOT:\(line)")
                }
            }
        }
    }
    
    // 3. Check /Volumes/.timemachine
    let tmHiddenRoot = "/Volumes/.timemachine"
    if let uuids = try? fm.contentsOfDirectory(atPath: tmHiddenRoot) {
        for uuid in uuids {
            let uuidPath = "\(tmHiddenRoot)/\(uuid)"
            if let backups = try? fm.contentsOfDirectory(atPath: uuidPath) {
                for backup in backups {
                    if backup.hasSuffix(".backup") {
                        points.append("\(uuidPath)/\(backup)")
                    }
                }
            }
        }
    }
    
    return points
}

func findVersions(for filePath: String, silent: Bool = false) -> [Version] {
    let fileUrl = URL(fileURLWithPath: filePath).standardized
    let fullPath = fileUrl.path
    let backupPoints = getBackupPoints()
    var versions: [Version] = []
    
    if !silent {
        print("Searching for versions of: \(fullPath)")
    }
    
    for point in backupPoints {
        if point.hasPrefix("SNAPSHOT:") {
            let snapName = String(point.dropFirst(9))
            let timestamp = snapName.components(separatedBy: ".").indices.contains(3) ? snapName.components(separatedBy: ".")[3] : snapName
            
            // Check if it's already mounted
            let mountedPath = "/Volumes/com.apple.TimeMachine.localsnapshots/Backups.backupdb"
            // We'll try to find it in the mounted snapshots if it exists
            if let computers = try? fm.contentsOfDirectory(atPath: mountedPath) {
                for computer in computers {
                    let potentialPath = "\(mountedPath)/\(computer)/\(timestamp)/Data\(fullPath)"
                    if fm.fileExists(atPath: potentialPath) {
                        versions.append(Version(path: potentialPath, timestamp: timestamp))
                        continue
                    }
                }
            }
            
            // If not found in mounted, we still list it as a target for tmutil restore
            // (But for simplicity in this prototype, we'll just show it if we can find it)
            continue
        }
        
        // Find the volume root inside the backup point (usually "Data" or "Macintosh HD")
        if let contents = try? fm.contentsOfDirectory(atPath: point) {
            for volumeRoot in contents {
                let potentialPath = "\(point)/\(volumeRoot)\(fullPath)"
                if fm.fileExists(atPath: potentialPath) {
                    // Extract timestamp from point path if possible
                    let timestamp = point.components(separatedBy: "/").last?.replacingOccurrences(of: ".previous", with: "").replacingOccurrences(of: ".backup", with: "") ?? "Unknown"
                    versions.append(Version(path: potentialPath, timestamp: timestamp))
                }
            }
        }
    }
    
    // Sort by timestamp descending
    versions.sort { $0.timestamp > $1.timestamp }
    return versions
}

if command == "list" {
    guard arguments.count > 2 else {
        print("Error: Missing file path")
        exit(1)
    }
    let isAlfred = arguments.contains("--alfred")
    let versions = findVersions(for: arguments[2], silent: isAlfred)
    
    if isAlfred {
        var items: [[String: Any]] = []
        for (idx, v) in versions.enumerated() {
            items.append([
                "title": v.timestamp,
                "subtitle": v.path,
                "arg": "\(idx)",
                "variables": ["file_path": arguments[2]],
                "icon": ["type": "fileicon", "path": arguments[2]]
            ])
        }
        let json: [String: Any] = ["items": items]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    } else {
        if versions.isEmpty {
            print("No versions found.")
        } else {
            print("\nAvailable versions:")
            for (idx, v) in versions.enumerated() {
                print("[\(idx)] \(v.timestamp) -> \(v.path)")
            }
        }
    }
} else if command == "restore" {
    guard arguments.count > 4, arguments[3] == "--index", let idx = Int(arguments[4]) else {
        print("Usage: retro restore <file_path> --index <n>")
        exit(1)
    }
    
    let versions = findVersions(for: arguments[2])
    guard idx >= 0 && idx < versions.count else {
        print("Error: Invalid index \(idx)")
        exit(1)
    }
    
    let source = versions[idx].path
    let destination = arguments[2]
    let restoredDest = destination + ".restored"
    
    print("Restoring version [\(idx)] to \(restoredDest)...")
    
    do {
        if fm.fileExists(atPath: restoredDest) {
            try fm.removeItem(atPath: restoredDest)
        }
        try fm.copyItem(atPath: source, toPath: restoredDest)
        print("Success! Restored to: \(restoredDest)")
    } catch {
        print("Restore failed: \(error)")
    }
} else {
    print("Unknown command: \(command)")
}
