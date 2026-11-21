import AppKit

// Claude Code runs this same binary with --hook for the island (IslandHook.swift)
if CommandLine.arguments.contains("--hook") { runHook() }
if CommandLine.arguments.contains("--self-test") { selfTest() }
// A hook that gave up mid-reply must not take the app down with it
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
