import Foundation
let fm = FileManager.default
let source = "/System/Volumes/Data/Applications/Safari.app"
let dest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Safari.app.test").path
if fm.fileExists(atPath: dest) { try? fm.removeItem(atPath: dest) }
do {
    try fm.copyItem(atPath: source, toPath: dest)
    print("Success: \(dest)")
} catch {
    print("Failed: \(error.localizedDescription)")
}
