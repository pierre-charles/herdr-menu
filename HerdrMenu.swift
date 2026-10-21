import AppKit
import ServiceManagement

// herdr's install script uses ~/.local/bin; Homebrew uses /opt/homebrew/bin (Apple silicon) or /usr/local/bin
let herdr = [NSHomeDirectory() + "/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
    .first(where: FileManager.default.isExecutableFile) ?? "herdr"

// MARK: - Menu actions

// (title, SF Symbol, herdr keybinding action, CLI args). The keybind shown comes from Keybinds below.
// "{pane}", "{tab}", "{workspace}" become the focused ids at click time; "{label}" prompts for a name.
typealias Action = (title: String, icon: String, binding: String, args: [String])

// The rows of a "Focus ›" style submenu, one per direction; herdr names the actions focus_pane_left etc.
func directionRows(_ verb: String, icons: [String]) -> [Action] {
    zip(["left", "right", "up", "down"], icons).map { dir, icon in (dir.capitalized, icon, "\(verb)_pane_\(dir)", ["pane", verb, "--direction", dir]) }
}

let paneActions: [Action] = [
    ("Split right", "rectangle.split.2x1", "split_vertical", ["pane", "split", "--direction", "right", "--focus"]),
    ("Split down", "rectangle.split.1x2", "split_horizontal", ["pane", "split", "--direction", "down", "--focus"]),
    ("Toggle zoom", "arrow.up.left.and.arrow.down.right", "zoom", ["pane", "zoom", "--toggle"]),
]
let paneSubmenus: [(title: String, icon: String, actions: [Action])] = [
    ("Focus", "rectangle.lefthalf.inset.filled",
     directionRows("focus", icons: ["rectangle.lefthalf.filled", "rectangle.righthalf.filled", "rectangle.tophalf.filled", "rectangle.bottomhalf.filled"])),
    ("Resize", "arrow.up.and.down.and.arrow.left.and.right",
     directionRows("resize", icons: ["arrow.left.to.line", "arrow.right.to.line", "arrow.up.to.line", "arrow.down.to.line"])),
    ("Swap", "rectangle.2.swap",
     directionRows("swap", icons: ["arrow.left.arrow.right", "arrow.left.arrow.right", "arrow.up.arrow.down", "arrow.up.arrow.down"])),
]
let closePane: Action = ("Close pane", "xmark.square", "close_pane", ["pane", "close", "{pane}"])
let tabActions: [Action] = [
    ("New tab…", "plus.rectangle.on.rectangle", "new_tab", ["tab", "create", "--label", "{label}", "--focus"]),
    ("Rename tab", "pencil", "rename_tab", ["tab", "rename", "{tab}", "{label}"]),
    ("Close tab", "xmark.rectangle", "close_tab", ["tab", "close", "{tab}"]),
]
let workspaceActions: [Action] = [
    ("New workspace…", "macwindow.badge.plus", "new_workspace", ["workspace", "create", "--label", "{label}", "--focus"]),
    ("Rename workspace", "square.and.pencil", "rename_workspace", ["workspace", "rename", "{workspace}", "{label}"]),
    ("Close workspace", "rectangle.badge.xmark", "close_workspace", ["workspace", "close", "{workspace}"]),
]

// MARK: - Keybinds

struct Keybinds {
    // herdr's defaults for the menu's actions: `herdr --default-config`, plus swap (missing there) from its keymap docs
    static let defaults = [
        "split_vertical": "prefix+v", "split_horizontal": "prefix+minus", "zoom": "prefix+z", "close_pane": "prefix+x",
        "focus_pane_left": "prefix+h", "focus_pane_right": "prefix+l", "focus_pane_up": "prefix+k", "focus_pane_down": "prefix+j",
        "swap_pane_left": "prefix+shift+h", "swap_pane_right": "prefix+shift+l",
        "swap_pane_up": "prefix+shift+k", "swap_pane_down": "prefix+shift+j", "resize_mode": "prefix+r",
        "new_tab": "prefix+c", "rename_tab": "prefix+shift+t", "close_tab": "prefix+shift+x",
        "new_workspace": "prefix+shift+n", "rename_workspace": "prefix+shift+w", "close_workspace": "prefix+shift+d",
    ]
    static let modifierSymbols = [("ctrl", "⌃"), ("alt", "⌥"), ("shift", "⇧"), ("cmd", "⌘"), ("super", "⌘")]
    static let keyNames = [
        "minus": "−", "plus": "+", "equal": "=", "comma": ",", "period": ".", "slash": "/", "backslash": "\\",
        "semicolon": ";", "quote": "'", "backtick": "`", "ampersand": "&", "left": "←", "right": "→", "up": "↑",
        "down": "↓", "enter": "↩", "tab": "⇥", "esc": "⎋", "space": "Space", "backspace": "⌫", "delete": "⌦",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]

    var prefix = "ctrl+b"
    var mine: [String: [String]] = [:] // [keys] action -> bindings
    var commands: [String] = [] // [[keys.command]] keys

    init(toml: String) {
        var section = ""
        for raw in toml.split(separator: "\n") {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                continue
            }
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            // The quoted strings in the value: odd pieces when split on quotes
            let values = kv[1].split(separator: "\"", omittingEmptySubsequences: false).enumerated()
                .filter { $0.offset % 2 == 1 && !$0.element.isEmpty }.map { String($0.element).lowercased() }
            if section == "keys", kv[0] == "prefix" {
                prefix = values.first ?? prefix
            } else if section == "keys" {
                mine[kv[0]] = values
            } else if section == "keys.command", kv[0] == "key" {
                commands += values
            }
        }
    }

    // The first active binding for a herdr action, nil when unbound
    func binding(_ action: String) -> String? {
        if let bindings = mine[action] { return bindings.first }
        guard let fallback = Self.defaults[action] else { return nil }
        return (mine.values.flatMap { $0 } + commands).contains(fallback) ? nil : fallback
    }

    // What the menu shows: (modifier column, key column), e.g. ("⌃B", "⇧N") or ("⌃⌥⇧", "←").
    // Resize falls back to resize mode plus an arrow when resize_pane_* isn't bound.
    func keys(for action: String) -> (String, String) {
        if let b = binding(action) { return display(b) }
        if action.hasPrefix("resize_pane_"), let mode = binding("resize_mode") {
            let (left, right) = display(mode)
            return (left, right + " " + Self.symbol(String(action.dropFirst("resize_pane_".count))))
        }
        return ("", "")
    }

    func display(_ binding: String) -> (String, String) {
        var parts = binding.split(separator: "+").map(String.init)
        let viaPrefix = parts.first == "prefix"
        if viaPrefix { parts.removeFirst() }
        let key = Self.symbol(parts.popLast() ?? "")
        let mods = Self.modifierSymbols.filter { parts.contains($0.0) }.map(\.1).joined()
        if viaPrefix {
            let (prefixMods, prefixKey) = display(prefix)
            return (prefixMods + prefixKey, mods + key)
        }
        return (mods, key)
    }

    static func symbol(_ key: String) -> String { keyNames[key] ?? key.uppercased() }
}

// MARK: - herdr

func run(_ args: [String], exe: String = herdr) -> (ok: Bool, out: Data, err: String) {
    let p = Process(), out = Pipe(), err = Pipe()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    // Drop herdr's caller context (HERDR_PANE_ID etc.) in case this app was launched from a herdr pane:
    // the CLI would treat that pane as the caller, so "current pane" and splits would ignore what's focused.
    p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HERDR_") }
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return (false, Data(), error.localizedDescription) }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    return (p.terminationStatus == 0, data, msg)
}

// herdr's JSON, decoded with .convertFromSnakeCase (agent_status -> agentStatus). Only the fields the menu uses.
struct Pane: Decodable { // also an agent: agents are panes with an agent in them
    let paneId, tabId, workspaceId: String
    let agent, agentStatus, terminalTitleStripped, cwd: String?
    let focused: Bool?
}
struct Group: Decodable { // a workspace, or a tab when tabId is set
    let workspaceId: String
    let tabId: String?
    let label: String
    let agentStatus: String?
    let focused: Bool?
    let paneCount: Int?
}
struct Snapshot: Decodable {
    let workspaces, tabs: [Group]
    let agents, panes: [Pane]
}
// Every command wraps its answer in "result" under a different key, so one type covers them all
struct Result: Decodable {
    let snapshot: Snapshot?
    let agents: [Pane]?
    let pane: Pane?
    let tab, workspace: Group?
}
struct Response: Decodable { let result: Result }

let decoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}()

func herdrResult(_ args: [String]) -> Result? {
    try? decoder.decode(Response.self, from: run(args).out).result
}

// What to call a pane or agent: its terminal title, else the agent, else its folder
func displayName(_ pane: Pane) -> String {
    [pane.terminalTitleStripped, pane.agent].compactMap { $0 }.first { !$0.isEmpty }
        ?? URL(fileURLWithPath: pane.cwd ?? "pane").lastPathComponent
}

func short(_ s: String, _ max: Int) -> String {
    s.count > max ? s.prefix(max - 1) + "…" : s
}

// A herdr TUI client is `herdr [--options]` or `herdr session attach <name>`.
// The long-lived server (`herdr server`) and one-shot CLI calls (`herdr pane ...`) don't count.
// ponytail: splits on spaces, so a herdr binary whose path contains a space is missed.
func isHerdrClient(_ command: String) -> Bool {
    let t = command.split(separator: " ")
    guard let exe = t.first, exe == "herdr" || exe.hasSuffix("/herdr") else { return false }
    return t.count == 1 || t[1].hasPrefix("-") || (t[1] == "session" && t.count > 2 && t[2] == "attach")
}

func herdrClientPID() -> String? {
    String(decoding: run(["-axo", "pid=,command="], exe: "/bin/ps").out, as: UTF8.self)
        .split(separator: "\n").lazy
        .map { $0.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init) }
        .first { $0.count == 2 && isHerdrClient($0[1]) }?[0]
}

// Bring forward the terminal app the herdr client runs in. macOS puts the launching app's
// bundle id in every child's environment as __CFBundleIdentifier (com.googlecode.iterm2 for iTerm2).
// openApplication is what the Dock does, so it works from a menu bar app where activate() may not.
// ponytail: raises the app's frontmost window, not necessarily the herdr one if the terminal has several.
func bringTerminalForward() {
    guard let pid = herdrClientPID() else { return }
    let env = String(decoding: run(["eww", "-o", "command=", "-p", pid], exe: "/bin/ps").out, as: UTF8.self)
    guard let entry = env.split(separator: " ").first(where: { $0.hasPrefix("__CFBundleIdentifier=") }),
          let id = entry.split(separator: "=", maxSplits: 1).last,
          let url = NSRunningApplication.runningApplications(withBundleIdentifier: String(id)).first?.bundleURL else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
}

// MARK: - Drawing

// Icon, title, then keybind right-aligned in grey, like Rectangle.
// The icon lives inside the title text: macOS hides NSMenuItem.image for this app, bundled or not.
func label(_ title: String, icon: String, keys: (String, String) = ("", ""), tint: NSColor? = nil) -> NSAttributedString {
    let font = NSFont.menuFont(ofSize: 0)
    let para = NSMutableParagraphStyle()
    // icon | title | prefix (right-aligned) | key (left-aligned), so "⌃B" and the keys each form a straight column
    para.tabStops = [
        NSTextTab(textAlignment: .left, location: 26),
        NSTextTab(textAlignment: .right, location: 200),
        NSTextTab(textAlignment: .left, location: 206),
    ]
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
    let att = NSTextAttachment()
    var config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
    if let tint { config = config.applying(.init(paletteColors: [tint])) }
    if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        att.image = img
        att.bounds = NSRect(x: 0, y: (font.capHeight - img.size.height) / 2, width: img.size.width, height: img.size.height)
    }
    let s = NSMutableAttributedString(attachment: att)
    s.addAttributes(attrs, range: NSRange(location: 0, length: s.length))
    s.append(NSAttributedString(string: "\t" + title, attributes: attrs))
    s.append(NSAttributedString(string: "\t\(keys.0)\t\(keys.1)", attributes: attrs.merging([.foregroundColor: NSColor.secondaryLabelColor]) { $1 }))
    return s
}

// Catppuccin Mocha on dark menus. On light ones Mocha's pastels wash out (about 1:1), so Latte's hues,
// darkened where needed to reach 3:1 against the light menu's grey (~#d5d6de)
func hex(dark: Int, light: Int) -> NSColor {
    NSColor(name: nil) { appearance in
        let v = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

// Agent status -> SF Symbol and colour, matching herdr's sidebar dots (src/client/shell.rs status_icon/status_color),
// in herdr's sort order (status_priority): blocked first, then done, working, idle, anything else last.
// ponytail: Catppuccin hard-coded, herdr's default theme; read [theme] from config.toml if I switch themes.
let statusStyles: [(status: String, symbol: String, color: NSColor)] = [
    ("blocked", "circlebadge.fill", hex(dark: 0xf38ba8, light: 0xd20f39)), // red
    ("done", "circlebadge.fill", hex(dark: 0x94e2d5, light: 0x148187)), // teal
    ("working", "circlebadge.fill", hex(dark: 0xf9e2af, light: 0xa26715)), // yellow
    ("idle", "circlebadge", hex(dark: 0xa6e3a1, light: 0x358423)), // green
]

func style(_ status: String?) -> (symbol: String, color: NSColor) {
    statusStyles.first { $0.status == status }.map { ($0.symbol, $0.color) } ?? ("circle.dotted", hex(dark: 0x6c7086, light: 0x6c7086)) // overlay0, 3.4:1 on light too
}

func rank(_ status: String?) -> Int {
    statusStyles.firstIndex { $0.status == status } ?? statusStyles.count
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var icon = NSImage(), notched = NSImage()
    let dot = NSView()
    var keybinds = Keybinds(toml: "")

    // The status badge: a 7pt dot in an 11pt notch cut from the icon's bottom-right corner.
    // The icon stays a template image (macOS tints it for light/dark); only the dot is coloured.
    let iconSize: CGFloat = 18, dotSize: CGFloat = 7, notchSize: CGFloat = 11

    func applicationDidFinishLaunching(_: Notification) {
        icon = Bundle.main.image(forResource: "sheep")
            ?? NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "herdr")!
        icon.size = NSSize(width: iconSize, height: iconSize)
        icon.isTemplate = true
        notched = NSImage(size: icon.size, flipped: false) { [icon, iconSize, dotSize, notchSize] r in
            icon.draw(in: r)
            let c = iconSize - dotSize / 2
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: c - notchSize / 2, y: dotSize / 2 - notchSize / 2, width: notchSize, height: notchSize)).fill()
            return true
        }
        notched.isTemplate = true
        status.button?.image = icon
        dot.wantsLayer = true
        dot.layer?.cornerRadius = dotSize / 2
        status.button?.addSubview(dot)

        status.menu = NSMenu()
        status.menu?.delegate = self

        refresh()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // Always running (a login item); the icon only shows while a herdr client is open.
    // A red dot means an agent is blocked on me, teal means one finished and I haven't looked yet.
    func refresh() {
        status.isVisible = herdrClientPID() != nil
        guard status.isVisible, let button = status.button else { return }
        let statuses = herdrResult(["agent", "list"])?.agents?.compactMap(\.agentStatus) ?? []
        let blocked = statuses.filter { $0 == "blocked" }.count, done = statuses.filter { $0 == "done" }.count
        let color = blocked > 0 ? style("blocked").color : done > 0 ? style("done").color : nil
        button.image = color == nil ? icon : notched
        dot.isHidden = color == nil
        // A CGColor is fixed when read, so resolve it for the menu bar's look (it can be dark in light mode)
        button.effectiveAppearance.performAsCurrentDrawingAppearance { self.dot.layer?.backgroundColor = color?.cgColor }
        // Same spot as the notch: the icon's bottom-right corner, wherever the button centres it
        let x0 = (button.bounds.width - iconSize) / 2, y0 = (button.bounds.height - iconSize) / 2
        dot.frame = NSRect(x: x0 + iconSize - dotSize, y: button.isFlipped ? y0 + iconSize - dotSize : y0,
                           width: dotSize, height: dotSize)
        let counts = [(blocked, "blocked"), (done, "done")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        button.toolTip = counts.isEmpty ? "herdr" : "Agents: " + counts.joined(separator: ", ")
    }

    // The whole menu is rebuilt from the live snapshot each time it opens:
    // Agents / Workspace / Tab / Pane (each named after the focused one) / Launch at login, Quit
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Reread my config so edits show up straight away
        let config = NSHomeDirectory() + "/.config/herdr/config.toml"
        keybinds = Keybinds(toml: (try? String(contentsOfFile: config, encoding: .utf8)) ?? "")
        let snap = herdrResult(["api", "snapshot"])?.snapshot
        let workspaces = snap?.workspaces ?? []
        let names = Dictionary((workspaces + (snap?.tabs ?? [])).map { ($0.tabId ?? $0.workspaceId, $0.label) }) { first, _ in first }

        // Named like herdr's sidebar: workspace, then the tab in grey
        menu.addItem(.sectionHeader(title: "Agents"))
        let agents = (snap?.agents ?? []).sorted { rank($0.agentStatus) < rank($1.agentStatus) }
        if agents.isEmpty { menu.addItem(NSMenuItem(title: "No agents", action: nil, keyEquivalent: "")) }
        for a in agents {
            menu.addItem(listRow(names[a.workspaceId] ?? displayName(a), detail: names[a.tabId] ?? displayName(a),
                                 status: a.agentStatus, focused: a.focused, args: ["agent", "focus", a.paneId]))
        }
        menu.addItem(.separator())

        // Then biggest to smallest, like herdr: workspace, tab, pane. Each header names the focused one,
        // which is where its actions land.
        let pane = snap?.panes.first { $0.focused == true }
        menu.addItem(header("Workspace", pane.flatMap { names[$0.workspaceId] }))
        for w in workspaces {
            menu.addItem(listRow(w.label, detail: "", status: w.agentStatus, focused: w.focused,
                                 args: ["workspace", "focus", w.workspaceId]))
        }
        add(workspaceActions, to: menu)
        menu.addItem(.separator())

        menu.addItem(header("Tab", pane.flatMap { names[$0.tabId] }))
        add(tabActions, to: menu)
        menu.addItem(.separator())

        menu.addItem(header("Pane", pane.map(displayName)))
        add(paneActions, to: menu)
        for sub in paneSubmenus {
            let mi = menuItem(sub.title, icon: sub.icon, action: nil)
            mi.submenu = NSMenu()
            sub.actions.forEach { mi.submenu?.addItem(item($0)) }
            menu.addItem(mi)
        }
        menu.addItem(item(closePane))
        menu.addItem(.separator())

        let login = menuItem("Launch at login", icon: "sunrise", action: #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let quit = menuItem("Quit", icon: "power", action: #selector(NSApplication.terminate))
        quit.target = NSApp
        menu.addItem(quit)
    }

    // "Pane · dev": a section header naming the thing its actions act on
    func header(_ kind: String, _ name: String?) -> NSMenuItem {
        .sectionHeader(title: name.map { "\(kind) · " + short($0, 30) } ?? kind)
    }

    // Every row: icon and title, optional keybind or detail column, and the CLI args to run when clicked
    func menuItem(_ title: String, icon: String, keys: (String, String) = ("", ""), tint: NSColor? = nil,
                  args: [String]? = nil, action: Selector? = #selector(App.click(_:))) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.attributedTitle = label(title, icon: icon, keys: keys, tint: tint)
        mi.representedObject = args
        mi.target = self
        return mi
    }

    func item(_ a: Action) -> NSMenuItem {
        menuItem(a.title, icon: a.icon, keys: keybinds.keys(for: a.binding), args: a.args)
    }

    // Each action's row. "New tab…" and "New workspace…" ask for a name first; holding ⌥ swaps each for a
    // quick version without the "…" or the name prompt, which creates straight away like herdr's own keybind.
    func add(_ actions: [Action], to menu: NSMenu) {
        for a in actions {
            menu.addItem(item(a))
            if a.title.hasSuffix("…") {
                let alt = item((String(a.title.dropLast()), a.icon, a.binding, a.args.filter { $0 != "--label" && $0 != "{label}" }))
                alt.isAlternate = true
                alt.keyEquivalentModifierMask = .option
                menu.addItem(alt)
            }
        }
    }

    // An agent or workspace row: herdr's status dot, name, grey detail, checkmark when focused
    func listRow(_ title: String, detail: String, status: String?, focused: Bool?, args: [String]) -> NSMenuItem {
        let (symbol, color) = style(status)
        // short() keeps the detail column straight
        let mi = menuItem(short(title, 26), icon: symbol, keys: ("", short(detail, 30)), tint: color, args: args)
        mi.state = focused == true ? .on : .off
        return mi
    }

    // A macOS login item (System Settings → General → Login Items), so the app starts at login.
    // It stays hidden until a herdr client is open, like any other time.
    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            alert("Couldn't change Launch at login: \(error.localizedDescription)")
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc func click(_ sender: NSMenuItem) {
        guard var args = sender.representedObject as? [String] else { return }
        var pane: Pane?
        if !Set(["{pane}", "{tab}", "{workspace}"]).isDisjoint(with: args) {
            guard let p = herdrResult(["pane", "current"])?.pane else { return alert("Couldn't find the focused herdr pane.") }
            pane = p
            let ids = ["{pane}": p.paneId, "{tab}": p.tabId, "{workspace}": p.workspaceId]
            args = args.map { ids[$0] ?? $0 }
        }
        // Confirmations follow Apple's alert guidelines: say what ends, name the button after the action,
        // style it as destructive, and keep Return on Cancel.
        if args.starts(with: ["pane", "close"]), let pane, let agent = pane.agent {
            guard ask("Close this pane?", "This ends the \(agent) agent running in “\(displayName(pane))”.",
                      button: "Close Pane", destructive: true) else { return }
        }
        // Closing or renaming a tab or workspace: args are [kind, verb, id, …], and `<kind> get <id>`
        // gives the current name and pane count
        let kind = args[0], isGroup = ["tab", "workspace"].contains(kind) && ["close", "rename"].contains(args[1])
        let group = isGroup ? herdrResult([kind, "get", args[2]]).flatMap { kind == "tab" ? $0.tab : $0.workspace } : nil
        // Tabs and workspaces always ask: everything inside them closes, agents included
        if isGroup, args[1] == "close" {
            let panes = group?.paneCount ?? 0
            let agents = (herdrResult(["agent", "list"])?.agents ?? [])
                .filter { (kind == "tab" ? $0.tabId : $0.workspaceId) == args[2] }.compactMap(\.agent)
            let ending = "its \(panes) pane\(panes == 1 ? "" : "s")"
            let who = agents.count == 1 ? "the \(agents[0]) agent" : "\(agents.count) agents (\(agents.joined(separator: ", ")))"
            guard ask("Close the \(kind) “\(group?.label ?? kind)”?",
                      agents.isEmpty ? "This ends \(ending)." : "This ends \(ending), including \(who) running there.",
                      button: "Close \(kind.capitalized)", destructive: true) else { return }
        }
        if let i = args.firstIndex(of: "{label}") {
            let creating = args[1] == "create"
            let field = NSTextField(string: group?.label ?? "") // renaming: prefilled with the current name
            field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
            guard ask(creating ? "New \(kind)" : "Rename \(kind)", "", button: creating ? "Create" : "Rename", field: field) else { return }
            if creating && field.stringValue.isEmpty {
                args.removeSubrange(i - 1...i) // no name: drop --label and let herdr choose
            } else {
                args[i] = field.stringValue
            }
        }
        let r = run(args)
        if r.ok { bringTerminalForward() } else { alert(r.err.isEmpty ? "herdr \(args.joined(separator: " ")) failed" : r.err) }
    }

    // A two-button dialog (button / Cancel), optionally with a text field. True if the button was pressed.
    // Destructive: the button is drawn red and Return presses Cancel instead.
    func ask(_ title: String, _ text: String, button: String, destructive: Bool = false, field: NSTextField? = nil) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        let action = a.addButton(withTitle: button)
        let cancel = a.addButton(withTitle: "Cancel")
        if destructive {
            action.hasDestructiveAction = true
            action.keyEquivalent = ""
            cancel.keyEquivalent = "\r"
        }
        if let field {
            a.accessoryView = field
            a.window.initialFirstResponder = field
        }
        NSApp.activate()
        return a.runModal() == .alertFirstButtonReturn
    }

    func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = "herdr"
        a.informativeText = text
        NSApp.activate()
        a.runModal()
    }
}

if CommandLine.arguments.contains("--self-test") {
    precondition(isHerdrClient("herdr"))
    precondition(isHerdrClient("/Users/me/.local/bin/herdr --session work"))
    precondition(isHerdrClient("herdr session attach work"))
    precondition(!isHerdrClient("/Users/me/.local/bin/herdr server"))
    precondition(!isHerdrClient("herdr pane split --direction right"))
    precondition(!isHerdrClient("herdr session list"))
    precondition(!isHerdrClient("/path/herdr-bar --watch-titles 3"))
    precondition(!isHerdrClient("vim herdr"))
    let k = Keybinds(toml: """
    [keys]
    prefix = "ctrl+a"  # a comment
    new_tab = ["prefix+t", "ctrl+alt+t"]
    close_tab = ""
    resize_pane_left = "ctrl+shift+alt+left"
    [[keys.command]]
    key = "prefix+k"
    command = "echo #not-a-key"
    """)
    precondition(k.keys(for: "new_tab") == ("⌃A", "T")) // first of a list, my prefix
    precondition(k.keys(for: "close_tab") == ("", "")) // "" unbinds
    precondition(k.keys(for: "focus_pane_up") == ("", "")) // default taken by a custom command
    precondition(k.keys(for: "split_horizontal") == ("⌃A", "−")) // default, my prefix, named key
    precondition(k.keys(for: "swap_pane_left") == ("⌃A", "⇧H"))
    precondition(k.keys(for: "resize_pane_left") == ("⌃⌥⇧", "←")) // direct binding
    precondition(k.keys(for: "resize_pane_up") == ("⌃A", "R ↑")) // resize mode fallback
    precondition(Keybinds(toml: "").keys(for: "new_workspace") == ("⌃B", "⇧N"))
    // herdr's JSON shape: snake_case keys, a "result" wrapper, extra fields ignored
    let sample = #"{"id":"x","result":{"type":"session_snapshot","snapshot":{"version":1,"workspaces":[{"workspace_id":"w1","label":"api","agent_status":"blocked","focused":true,"tab_count":1}],"tabs":[{"tab_id":"w1:t1","workspace_id":"w1","label":"auth","pane_count":2}],"agents":[{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","agent":"claude","agent_status":"blocked","focused":true,"revision":3}],"panes":[{"pane_id":"w1:p2","tab_id":"w1:t1","workspace_id":"w1","focused":false,"cwd":"/tmp/site","terminal_title_stripped":""}]}}}"#
    let snap = try! decoder.decode(Response.self, from: Data(sample.utf8)).result.snapshot!
    precondition(snap.workspaces[0].label == "api" && snap.workspaces[0].tabId == nil && snap.tabs[0].paneCount == 2)
    precondition(snap.agents[0].agentStatus == "blocked" && displayName(snap.agents[0]) == "claude")
    precondition(displayName(snap.panes[0]) == "site") // empty title falls back to the folder
    precondition(rank("blocked") < rank("idle") && rank("idle") < rank(nil))
    print("self-test ok")
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
