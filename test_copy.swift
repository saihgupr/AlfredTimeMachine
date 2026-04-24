import Foundation
let fm = FileManager.default
let source = "/System/Volumes/Data/Applications/Safari.app"
let dest = "/tmp/Safari.app.test"
if fm.fileExists(atPath: dest) { try? fm.removeItem(atPath: dest) }
do {
    try fm.copyItem(atPath: source, toPath: dest)
    print("Success")
} catch {
    print("Failed: \(error.localizedDescription)")
}
