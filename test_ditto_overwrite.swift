import Foundation

let fm = FileManager.default
let source = "/System/Volumes/Data/Applications/Safari.app"
let dest = "/tmp/SafariTest.app"

if fm.fileExists(atPath: dest) { try? fm.removeItem(atPath: dest) }

do {
    try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    task.arguments = [source, dest]
    try? task.run()
    task.waitUntilExit()
    print("ditto exited with: \(task.terminationStatus)")
} catch {
    print("error")
}
