import Foundation

let fm = FileManager.default
let source = "/tmp/fake_app.app"
let dest = "/tmp/fake_dest.app"

try? fm.removeItem(atPath: source)
try? fm.removeItem(atPath: dest)

try! fm.createDirectory(atPath: source, withIntermediateDirectories: true)
try! fm.createDirectory(atPath: source + "/Contents", withIntermediateDirectories: true)

// simulate copyItem leaving an empty dir
try! fm.createDirectory(atPath: dest, withIntermediateDirectories: true)

let task2 = Process()
task2.executableURL = URL(fileURLWithPath: "/bin/cp")
task2.arguments = ["-R", source, dest]
try! task2.run()
task2.waitUntilExit()

let task3 = Process()
task3.executableURL = URL(fileURLWithPath: "/bin/ls")
task3.arguments = ["-la", dest]
try! task3.run()
task3.waitUntilExit()
