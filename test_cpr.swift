import Foundation

func runProcess(_ exec: String, args: [String]) -> (Int32, String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: exec)
    task.arguments = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    try? task.run()
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

let (status, out) = runProcess("/bin/cp", args: ["-R", "/Applications/Safari.app", "/tmp/Safari.app.test4"])
print("Status: \(status), Out: \(out)")
