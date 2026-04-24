import Foundation

func resolveInputPath(_ rawPath: String) -> String {
    var path = URL(fileURLWithPath: rawPath).standardized.path
    if path.hasPrefix("/System/Volumes/Data") {
        path = String(path.dropFirst("/System/Volumes/Data".count))
    }
    return path
}

let input = "/Users/username/Projects/CurrentProjects/AlfredTimeMachine/retro.swift"
print("Input: \(input)")
print("Resolved: \(resolveInputPath(input))")
