// Standalone, headless metadata relay. No OAuth credentials or network requests.
import Foundation
import CryptoKit
import CoreFoundation
import Darwin
signal(SIGPIPE, SIG_IGN)

let args = CommandLine.arguments
func argument(_ name: String) -> String? {
  guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
  return args[index + 1]
}
func object(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
func read(_ url: URL) -> [String: Any] { guard let data = try? Data(contentsOf: url) else { return [:] }; return object(data) }
func atomic(_ value: [String: Any], _ url: URL) throws {
  let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  try data.write(to: url, options: .atomic)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
func number(_ value: Any?) -> Double? {
  guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
  return value.doubleValue
}
func window(_ value: Any?) -> [String: Any]? {
  guard let map = value as? [String: Any], let used = number(map["used_percentage"]), (0...100).contains(used) else { return nil }
  var result: [String: Any] = ["used_percentage": used]
  if let reset = number(map["resets_at"]), reset > 0, reset < 4102444800 { result["resets_at"] = reset }
  return result
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let root = argument("--root"), let identity = argument("--identity"), input.count <= 8 * 1024 * 1024 else { exit(0) }
let privateDirectory = URL(fileURLWithPath: root).appendingPathComponent("quotamate", isDirectory: true)
let data = object(input)
var rates: [String: Any] = [:]
if let raw = data["rate_limits"] as? [String: Any] {
  for key in ["five_hour", "seven_day"] { if let value = window(raw[key]) { rates[key] = value } }
  do {
    try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: privateDirectory.path)
    let sessions = privateDirectory.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let session = data["session_id"] as? String ?? "unknown"
    let digest = SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
    let bindingFile = sessions.appendingPathComponent(digest + ".json")
    var binding = read(bindingFile)["identity"] as? String
    if binding == nil { try atomic(["identity": identity], bindingFile); binding = identity }
    // An older still-running session must not overwrite a newly connected account.
    if binding == identity {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      try atomic(["identity": identity, "capturedAt": formatter.string(from: Date()), "rate_limits": rates], privateDirectory.appendingPathComponent("usage.json"))
    }
  } catch { /* Metadata collection must never interrupt Claude Code. */ }
}

let original = read(privateDirectory.appendingPathComponent("original-statusline.json"))["statusLine"] as? [String: Any]
if let command = original?["command"] as? String, !command.isEmpty, !command.contains("quotamate-claude-statusline") {
  let process = Process(), pipe = Pipe(), stdin = Pipe()
  process.executableURL = URL(fileURLWithPath: "/bin/sh")
  process.arguments = ["-c", command]
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  process.standardInput = stdin
  do {
    try process.run()
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: timeout)
    DispatchQueue.global().async {
      try? stdin.fileHandleForWriting.write(contentsOf: input)
      try? stdin.fileHandleForWriting.close()
    }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    timeout.cancel()
    FileHandle.standardOutput.write(output)
    exit(0)
  } catch { /* Fall back to a compact status line. */ }
}
var parts = ["Claude"]
for (key, label) in [("five_hour", "5h"), ("seven_day", "7d")] {
  if let map = rates[key] as? [String: Any], let used = number(map["used_percentage"]) { parts.append("\(label) \(Int(used.rounded()))%") }
}
print(parts.joined(separator: " · "))
