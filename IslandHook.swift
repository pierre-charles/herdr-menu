import Foundation

// Claude Code runs `HerdrMenu --hook`, which forwards the hook input to the running app over this socket.
// For PermissionRequest it waits for the app's reply and prints it as the hook's output.
let socketPath = NSHomeDirectory() + "/Library/Application Support/herdr-menu/hook.sock"

private func withAddress<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        _ = socketPath.withCString { strncpy(buf.baseAddress!.assumingMemoryBound(to: CChar.self), $0, buf.count - 1) }
    }
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { buf in
        var offset = 0
        while offset < buf.count {
            let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
            if n <= 0 { return }
            offset += n
        }
    }
}

func readLine(_ fd: Int32) -> Data? {
    var line = Data()
    var byte: UInt8 = 0
    while read(fd, &byte, 1) == 1 {
        if byte == 10 { return line }
        line.append(byte)
    }
    return nil
}

func runHook() -> Never {
    signal(SIGPIPE, SIG_IGN)
    let input = FileHandle.standardInput.readDataToEndOfFile()
    // Only sessions in a herdr or Rex pane (herdr first: it's the inner one when herdr runs inside Rex),
    // and only while the app is running; otherwise Claude carries on as normal
    let env = ProcessInfo.processInfo.environment
    guard let block = env["HERDR_PANE_ID"] ?? env["REX_BLOCK"],
          var hook = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else { exit(0) }
    hook["rex_block"] = block
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard withAddress({ connect(fd, $0, $1) }) == 0, var data = try? JSONSerialization.data(withJSONObject: hook) else { exit(0) }
    data.append(10)
    writeAll(fd, data)
    if hook["hook_event_name"] as? String == "PermissionRequest", let reply = readLine(fd) {
        FileHandle.standardOutput.write(reply)
    }
    exit(0)
}

func startHookServer(_ handle: @escaping ([String: Any], Int32) -> Void) {
    try? FileManager.default.createDirectory(atPath: (socketPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    unlink(socketPath)
    let server = socket(AF_UNIX, SOCK_STREAM, 0)
    guard withAddress({ bind(server, $0, $1) }) == 0 else { return }
    chmod(socketPath, 0o600)
    listen(server, 16)
    Thread {
        while true {
            let fd = accept(server, nil, nil)
            if fd < 0 { continue }
            DispatchQueue.global().async {
                guard let line = readLine(fd), let hook = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                    close(fd)
                    return
                }
                DispatchQueue.main.async { handle(hook, fd) }
            }
        }
    }.start()
}

// MARK: Installing the hooks

let claudeSettings = NSHomeDirectory() + "/.claude/settings.json"
let hookCommand = "'" + (Bundle.main.executablePath ?? "") + "' --hook"

func claudeHooksInstalled() -> Bool {
    ((try? String(contentsOfFile: claudeSettings, encoding: .utf8)) ?? "").contains(hookCommand.dropFirst())
}

// Python rather than JSONSerialization so settings.json keeps its key order. Removes this app's hooks and the
// standalone Rex Island's from before the island moved into the menu, then adds them back unless removing.
// PreToolUse and UserPromptSubmit are async so Claude never waits; PermissionRequest waits for a click.
let hooksScript = """
import json, os, sys
command, mode = sys.argv[1], sys.argv[2]
path = os.path.expanduser("~/.claude/settings.json")
settings = json.load(open(path)) if os.path.exists(path) else {}
hooks = settings.setdefault("hooks", {})
ours = lambda h: "--hook" in h.get("command", "") and ("HerdrMenu" in h["command"] or "RexIsland" in h["command"])
for event in list(hooks):
    hooks[event] = [g for g in hooks[event] if not any(ours(h) for h in g.get("hooks", []))]
    if not hooks[event]:
        del hooks[event]
if mode == "install":
    hooks.setdefault("PreToolUse", []).append({"matcher": "*", "hooks": [{"type": "command", "command": command, "async": True}]})
    hooks.setdefault("UserPromptSubmit", []).append({"hooks": [{"type": "command", "command": command, "async": True}]})
    hooks.setdefault("PermissionRequest", []).append({"matcher": "*", "hooks": [{"type": "command", "command": command, "timeout": 86400}]})
if not hooks:
    del settings["hooks"]
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(settings, open(path, "w"), indent=2, ensure_ascii=False)
"""

// Returns an error message, or nil when it worked
func setClaudeHooks(installed: Bool) -> String? {
    let r = run(["-c", hooksScript, hookCommand, installed ? "install" : "remove"], exe: "/usr/bin/python3")
    return r.ok ? nil : "Couldn't update ~/.claude/settings.json: \(r.err)"
}
