import Foundation
let fm = FileManager.default
let tmHidden = "/Volumes/.timemachine"
var found = [String]()

let targetPath = "/Applications/Dia.app"

if let uuids = try? fm.contentsOfDirectory(atPath: tmHidden) {
    for uuid in uuids {
        let uuidPath = "\(tmHidden)/\(uuid)"
        if let backups = try? fm.contentsOfDirectory(atPath: uuidPath) {
            for backup in backups where backup.hasSuffix(".backup") {
                let backupPath = "\(uuidPath)/\(backup)"
                if let subDirs = try? fm.contentsOfDirectory(atPath: backupPath) {
                    for sub in subDirs {
                        let volumePath = "\(backupPath)/\(sub)"
                        let dataCandidate = "\(volumePath)/Data\(targetPath)"
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: dataCandidate, isDirectory: &isDir) {
                            found.append(dataCandidate)
                        } else {
                            print("Tried and failed: \(dataCandidate)")
                        }
                    }
                } else {
                    print("Failed to read: \(backupPath)")
                }
            }
        } else {
            print("Failed to read UUID path: \(uuidPath)")
        }
    }
}
print("Found: \(found)")
