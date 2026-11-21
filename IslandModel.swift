import AppKit
import SwiftUI

let ear: CGFloat = 28 // just enough for a 14pt icon or a two-digit count, so the pill covers as little menu bar as possible
let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)

/// One agent: a Rex pane's program status as printed by islandStatusScript, or a herdr agent (herdr: true)
/// with its workspace as the session
struct Item: Decodable, Identifiable {
    let session, label, block, state: String
    let kind, app, msg, updated: String?
    var herdr: Bool? = nil
    var id: String { block }

    var updatedDate: Date? { updated.flatMap { ISO8601DateFormatter().date(from: String($0.prefix(19)) + "Z") } }
}

struct StatusSnapshot: Decodable {
    let items: [Item]
    let visible: String?
}

/// A PermissionRequest hook waiting on its socket for Allow or Deny
struct Request: Identifiable {
    let id = UUID()
    let block, tool: String
    let input: [String: Any]
    let suggestions: [Any]
    let fd: Int32
    let source: DispatchSourceRead
}

struct Geometry: Equatable {
    var frame: NSRect
    var notch: CGFloat
    var height: CGFloat

    // ponytail: always the notched screen, add a screen picker if you want it on the external display
    static func current() -> Geometry {
        let screen = NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main!
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY // 0 when the menu bar hides itself
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let notch = screen.safeAreaInsets.top
            let height = setting(Setting.islandHeight) == "menubar" ? max(menuBar, notch) : notch
            return Geometry(frame: screen.frame, notch: r.minX - l.maxX, height: height)
        }
        return Geometry(frame: screen.frame, notch: 0, height: max(menuBar, 24))
    }
}

enum Mode: Equatable { case collapsed, peek(String), full }

final class Model: ObservableObject {
    @Published var items: [Item] = []
    // The two sources items come from: islandStatusScript for Rex, the menu's refresh for herdr
    var rexItems: [Item] = [], herdrItems: [Item] = []
    /// The herdr workspace on screen: the focused one, while the terminal running herdr is in front
    var herdrShowing: String?
    @Published var requests: [Request] = []
    @Published var unseen: Set<String> = []
    @Published var activity: [String: String] = [:]
    @Published var prompts: [String: String] = [:]
    @Published var since: [String: Date] = [:]
    @Published var hovering = false
    @Published var peek: String?
    @Published var hoveredRow: String?
    var visible: String? { didSet { if visible != oldValue { markSeen() } } }
    @Published var geo = Geometry.current() // published, so a Height or display scaling change redraws the pill
    var contentSize: CGSize { didSet { if contentSize != oldValue { updateWindow() } } }
    private var lastState: [String: String] = [:]
    private var peekToken = UUID()
    private var shrink: DispatchWorkItem?
    let panel: NSPanel

    init(panel: NSPanel) {
        self.panel = panel
        let start = Geometry.current()
        contentSize = CGSize(width: start.notch, height: start.height)
    }

    var mode: Mode { hovering ? .full : peek.map { .peek($0) } ?? .collapsed }
    var blocked: [Item] { items.filter { $0.state == "blocked" } }
    var working: [Item] { items.filter { $0.state == "working" } }
    var showEars: Bool { !blocked.isEmpty || !unseen.isEmpty || !working.isEmpty || !requests.isEmpty || geo.notch == 0 }
    var collapsedWidth: CGFloat { geo.notch + (showEars ? 2 * ear : 0) }
    var panelWidth: CGFloat { requests.contains { $0.tool == "ExitPlanMode" } ? 540 : 440 }
    func item(_ block: String) -> Item? { items.first { $0.block == block } }

    // MARK: Rex status

    func apply(_ new: [Item]) {
        let present = Set(new.map(\.block))
        // Store the new statuses before dropping anything down, or the card shows the old one
        withAnimation(spring) { items = new }
        for i in new {
            let old = lastState[i.block]
            if old != i.state { since[i.block] = old == nil ? i.updatedDate ?? .now : .now }
            if let old, old != i.state {
                if old == "blocked" { requests.filter { $0.block == i.block }.forEach(drop) }
                if i.state == "done", !onScreen(i.block) {
                    unseen.insert(i.block)
                    notify(i.block, sound: "Glass", seconds: 4)
                }
                if i.state == "blocked" { notify(i.block, sound: "Funk", seconds: 12) }
            }
            if i.state != "done" { unseen.remove(i.block) }
        }
        requests.filter { !present.contains($0.block) }.forEach(drop)
        unseen.formIntersection(present) // a closed pane can't be looked at any more
        lastState = Dictionary(new.map { ($0.block, $0.state) }) { a, _ in a }
    }

    /// Most urgent first: blocked, error, finished and unseen, working, then the rest
    var sorted: [Item] {
        func rank(_ i: Item) -> Int {
            i.state == "done" && unseen.contains(i.block) ? 2 : ["blocked": 0, "error": 1, "working": 3, "done": 4][i.state] ?? 5
        }
        return items.sorted { (rank($0), $0.label) < (rank($1), $1.label) }
    }

    /// Like Rex's own dot: a finished agent stays unseen until Rex is in front showing its session
    func markSeen() {
        guard rexInFront, let visible else { return }
        let seen = items.filter { $0.session == visible }.map(\.block)
        if !unseen.isDisjoint(with: seen) { withAnimation(spring) { unseen.subtract(seen) } }
    }

    func watch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: rexCLI)
        // Without --autostart=false, restarting this every 2s would start the Rex server whenever it's down
        p.arguments = ["--autostart=false", "do", "--all", "-e", islandStatusScript]
        p.environment = cliEnvironment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil; return }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 10) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                if let snap = try? JSONDecoder().decode(StatusSnapshot.self, from: line) {
                    DispatchQueue.main.async {
                        self.visible = snap.visible
                        self.rexItems = snap.items
                        self.apply(self.rexItems + self.herdrItems)
                    }
                }
            }
        }
        // Rex server restarts end the script, so start it again
        p.terminationHandler = { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.watch() } }
        try? p.run()
    }

    // MARK: Claude hooks

    func hook(_ hook: [String: Any], fd: Int32) {
        let block = hook["rex_block"] as? String ?? ""
        let tool = hook["tool_name"] as? String ?? ""
        let input = hook["tool_input"] as? [String: Any] ?? [:]
        switch hook["hook_event_name"] as? String {
        case "UserPromptSubmit":
            prompts[block] = hook["prompt"] as? String
            activity[block] = "Thinking"
        case "PreToolUse":
            activity[block] = describe(tool, input)
        case "PermissionRequest" where tool != "AskUserQuestion":
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            let request = Request(block: block, tool: tool, input: input, suggestions: hook["permission_suggestions"] as? [Any] ?? [], fd: fd, source: source)
            // The hook going away means Claude moved on, e.g. you answered in the terminal
            source.setEventHandler { [self] in
                var byte: UInt8 = 0
                if read(fd, &byte, 1) <= 0 { drop(request) }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            withAnimation(spring) { requests.append(request) }
            notify(block, sound: nil, seconds: 20)
            return
        default:
            break
        }
        close(fd)
    }

    func reply(_ r: Request, allow: Bool, always: Bool = false) {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if allow {
            // ExitPlanMode needs its input echoed back, and for other tools it's a no-op
            decision["updatedInput"] = r.input
            if always { decision["updatedPermissions"] = r.suggestions }
        } else {
            decision["message"] = r.tool == "ExitPlanMode"
                ? "The user wants to keep planning. Wait for their feedback."
                : "The user denied this from Rex Island."
        }
        let output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        if var data = try? JSONSerialization.data(withJSONObject: output) {
            data.append(10)
            writeAll(r.fd, data)
        }
        drop(r)
    }

    func drop(_ r: Request) {
        r.source.cancel()
        withAnimation(spring) { requests.removeAll { $0.id == r.id } }
        if peek == r.block, !requests.contains(where: { $0.block == r.block }) { withAnimation(spring) { peek = nil } }
    }

    func describe(_ tool: String, _ input: [String: Any]) -> String {
        let file = (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
        switch tool {
        case "Read": return "Reading \(file ?? "a file")"
        case "Edit", "MultiEdit", "NotebookEdit": return "Editing \(file ?? "a file")"
        case "Write": return "Writing \(file ?? "a file")"
        case "Bash": return "Running \((input["command"] as? String ?? "").split(separator: "\n").first ?? "")"
        case "Grep", "Glob": return "Searching \(input["pattern"] as? String ?? "")"
        case "WebFetch": return "Reading \(URL(string: input["url"] as? String ?? "")?.host ?? "the web")"
        case "WebSearch": return "Searching the web"
        case "Agent", "Task": return "Agent: \(input["description"] as? String ?? "working")"
        default: return tool
        }
    }

    // MARK: Window

    var rexInFront: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == rexBundle }

    /// Its session is on screen, in Rex or herdr, so you can already see it
    func onScreen(_ block: String) -> Bool {
        guard let i = item(block) else { return false }
        return i.herdr == true ? i.session == herdrShowing : visible != nil && i.session == visible && rexInFront
    }

    /// herdr's agents from the menu's refresh, nil while herdr is closed. herdr's own done already means
    /// "finished and not looked at": viewing it turns it idle, which clears the island's ✓ too.
    func setHerdr(_ snap: Snapshot?, terminalInFront: Bool) {
        let names = Dictionary((snap?.workspaces ?? []).map { ($0.workspaceId, $0.label) }) { first, _ in first }
        herdrShowing = terminalInFront ? snap?.workspaces.first { $0.focused == true }?.workspaceId : nil
        let new = (snap?.agents ?? []).map { a in
            Item(session: a.workspaceId, label: names[a.workspaceId] ?? displayName(a), block: a.paneId,
                 state: a.agentStatus == "unknown" ? "idle" : a.agentStatus ?? "idle", kind: nil, app: a.agent, msg: nil, updated: nil, herdr: true)
        }
        guard new.map(\.block) != herdrItems.map(\.block) || new.map(\.state) != herdrItems.map(\.state) else { return }
        herdrItems = new
        apply(rexItems + herdrItems)
    }

    func notify(_ block: String, sound: String?, seconds: Double) {
        guard !onScreen(block) else { return }
        if let sound, setting(Setting.islandSounds) == "on" { NSSound(named: sound)?.play() }
        withAnimation(spring) { peek = block }
        let token = UUID()
        peekToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
            if peekToken == token, !requests.contains(where: { $0.block == block }) { withAnimation(spring) { peek = nil } }
        }
    }

    var pillRect: NSRect {
        NSRect(x: geo.frame.midX - contentSize.width / 2, y: geo.frame.maxY - contentSize.height,
               width: contentSize.width, height: contentSize.height)
    }

    /// Grow the window straight away, shrink it once the collapse animation has finished
    func updateWindow() {
        panel.setFrame(panel.frame.width > 0 ? panel.frame.union(pillRect) : pillRect, display: true)
        shrink?.cancel()
        let work = DispatchWorkItem { [self] in panel.setFrame(pillRect, display: true) }
        shrink = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func trackMouse() {
        let inside = pillRect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        guard inside != hovering else { return }
        withAnimation(spring) {
            hovering = inside
            if !inside {
                hoveredRow = nil
                if !requests.contains(where: { $0.block == peek }) { peek = nil }
            }
        }
    }

    func jump(_ block: String) {
        guard let i = item(block) else { return }
        unseen.remove(block)
        let (args, backend) = i.herdr == true ? (["agent", "focus", i.block], Backend.herdr) : (rexShow(session: i.session, block: i.block), .rex)
        DispatchQueue.global().async {
            if run(args, exe: backend.exe).ok { DispatchQueue.main.async { bringTerminalForward(backend) } }
        }
    }
}

// Prints one JSON line with every pane's program status at start and on each change, plus the session the Rex
// app shows (see rexVisibleScript). Run with `rex do --all`, which keeps it going while its handlers are registered.
let islandStatusScript = """
-- Prints one JSON line with every pane's program status, then again on each change.
-- `visible` is the session the Rex app last showed, or nil until you switch sessions.
local visible

local function snapshot()
  local items = {}
  -- attach_all also picks up sessions created since the last snapshot
  local all = rex.call("session.attach_all", { event_scope = "session" }) or {}
  for _, s in ipairs(all.sessions or {}) do
    local blocks = rex.call("session.list_blocks", { session_id = s.session_id }) or {}
    for _, b in ipairs(blocks.blocks or {}) do
      if b.placement == "placed" then
        local st = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "program_status" }) or {}
        for _, r in ipairs(st.records or {}) do
          if r.id == nil then
            items[#items + 1] = {
              session = s.session_id, label = s.label, block = b.block_id,
              state = r.state, kind = r.kind, app = r.effective_app, msg = r.msg, updated = r.updated_at,
            }
          end
        end
      end
    end
  end
  -- an empty Lua table encodes as {}, so spell out the empty list
  print((rex.json.encode({ items = items, visible = visible }):gsub('"items":{}', '"items":[]')))
end

local pending = false
local function changed()
  if pending then return end
  pending = true
  rex.after(0.2, function() pending = false; snapshot() end)
end

for _, ev in ipairs({ "terminal.program_status_changed", "terminal.program_status_removed",
  "session_label_changed", "block_closed", "session_created", "session_destroyed" }) do
  rex.on(ev, changed)
end

-- ponytail: Rex has no "session shown" event, but the app re-sends a session's terminal sizes
-- each time it shows it, so the last session the app resized is the one on screen
rex.on("terminal.size_changed", function(ctx, ev)
  for _, c in ipairs((rex.call("client.list") or {}).clients or {}) do
    if c.client_id == ev.owner and c.info.kind == "app" and visible ~= ctx.session_id then
      visible = ctx.session_id
      changed()
    end
  end
end)
snapshot()
"""

// A non-activating panel at the top of the notched screen; the menu shows it while the Rex app is open
final class Island {
    let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let model: Model

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        model = Model(panel: panel)
        panel.contentView = IslandHostingView(rootView: IslandView(m: model))
        model.updateWindow()
        model.watch()
        startHookServer { [model] in model.hook($0, fd: $1) }

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [model] _ in
            model.geo = .current()
            model.updateWindow()
        }
        center.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [model] _ in
            model.objectWillChange.send()
        }
        // Coming back to Rex counts as looking at the session it shows
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [model] _ in
            model.markSeen()
        }
        // Global sees moves over other apps, local sees moves over the island itself
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [model] _ in model.trackMouse() }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [model] in model.trackMouse(); return $0 }
    }

    // Called on every refresh, so a Height change in the menu applies straight away
    func show(_ on: Bool) {
        guard on else { return panel.orderOut(nil) }
        if Geometry.current() != model.geo {
            model.geo = .current()
            model.updateWindow()
        }
        panel.orderFrontRegardless()
    }
}

/// Never moved below the menu bar, which is where macOS puts windows it considers misplaced
final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// A non-activating panel never becomes key, so let the first click land
final class IslandHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
