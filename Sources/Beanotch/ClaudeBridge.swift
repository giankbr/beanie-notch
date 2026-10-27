import AppKit
import Network

// Claude Code in the notch. Claude Code's hooks post each event to a small server on 127.0.0.1 here: what's
// being worked on, when it's done or waiting, and permission requests, which Beanotch can answer. When Beanotch isn't
// running, or no answer comes in time, the hook returns nothing and Claude Code asks in the terminal as usual.
@MainActor
final class ClaudeBridge: ObservableObject {
    struct Session: Identifiable, Equatable {
        enum State { case working, waiting, done }
        let id: String
        var project: String
        var state: State
        var updated: Date
    }

    struct Request: Identifiable, Equatable {
        let id = UUID()
        let project: String
        let tool: String
        let detail: String
    }

    static let port: UInt16 = 47823

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var pending: [Request] = []
    @Published private(set) var installed = false
    var onNotice: ((Notice) -> Void)?
    var onRequest: (() -> Void)?
    private var listener: NWListener?
    private var waiting: [UUID: NWConnection] = [:]

    var working: Session? { sessions.first { $0.state == .working } }

    private static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Beanotch")
    }
    private static var tokenURL: URL { supportFolder.appendingPathComponent("hook-token") }
    private static var settingsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }

    // A random token in a file only this user can read: the hook sends it, so web pages can't post here.
    private lazy var token: String = {
        if let saved = try? String(contentsOf: Self.tokenURL, encoding: .utf8), saved.count >= 32 { return saved }
        let fresh = (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
        try? FileManager.default.createDirectory(at: Self.supportFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.tokenURL.path, contents: Data(fresh.utf8), attributes: [.posixPermissions: 0o600])
        return fresh
    }()

    init() {
        installed = Self.hooksInstalled()
    }

    func setEnabled(_ on: Bool) {
        if on {
            _ = token
            start()
            if Self.hooksInstalled(Array(Self.markers.dropFirst())) { Self.removeHooks() }
            if !Self.hooksInstalled() { Self.installHooks() }
        } else {
            listener?.cancel()
            listener = nil
            answerAll(nil)
            if Self.hooksInstalled(Self.markers) { Self.removeHooks() }
            sessions = []
        }
        installed = Self.hooksInstalled()
    }

    func answer(_ request: Request, allow: Bool?) {
        pending.removeAll { $0.id == request.id }
        guard let connection = waiting.removeValue(forKey: request.id) else { return }
        Self.reply(connection, body: allow.map(Self.decision) ?? "")
    }

    private func answerAll(_ allow: Bool?) {
        for request in pending { answer(request, allow: allow) }
    }

    // MARK: Server

    func start() {
        guard listener == nil else { return }
        _ = token
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { return }
        weak let bridge = self
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            Self.receive(connection, buffer: Data()) { request in
                MainActor.assumeIsolated { bridge?.handle(request, on: connection) }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    struct HTTPRequest { let token: String; let body: Data }

    // Reads the headers, then as much body as Content-Length says.
    nonisolated static func receive(_ connection: NWConnection, buffer: Data, done: @escaping @Sendable (HTTPRequest) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                var fields: [String: String] = [:]
                for line in head.split(separator: "\r\n").dropFirst() {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 { fields[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces) }
                }
                let length = Int(fields["content-length"] ?? "") ?? 0
                let body = buffer[end.upperBound...]
                if body.count >= length || complete {
                    done(HTTPRequest(token: fields["x-beanotch-token"] ?? "", body: Data(body.prefix(length))))
                    return
                }
            }
            if complete || error != nil || buffer.count > 4 << 20 { connection.cancel(); return }
            receive(connection, buffer: buffer, done: done)
        }
    }

    nonisolated static func reply(_ connection: NWConnection, body: String) {
        let data = Data(body.utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }

    nonisolated private static func decision(_ allow: Bool) -> String {
        let decision: [String: Any] = allow ? ["behavior": "allow"] : ["behavior": "deny", "message": "Denied from Beanotch"]
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: output)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        guard request.token == token,
              let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let event = json["hook_event_name"] as? String else {
            Self.reply(connection, body: "")
            return
        }
        let id = json["session_id"] as? String ?? "?"
        let project = (json["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code"
        switch event {
        case "UserPromptSubmit":
            update(id, project, .working)
            Self.reply(connection, body: "")
        case "Stop":
            update(id, project, .done)
            onNotice?(Notice(icon: "checkmark.circle.fill", color: Theme.accent, left: "Claude finished", right: project, duration: 6, essential: true))
            Self.reply(connection, body: "")
        case "Notification":
            if json["notification_type"] as? String == "idle_prompt" {
                update(id, project, .waiting)
                onNotice?(Notice(icon: "ellipsis.bubble.fill", color: Theme.amber, left: "Claude is waiting", right: project, duration: 6, essential: true))
            }
            Self.reply(connection, body: "")
        case "PermissionRequest":
            update(id, project, .waiting)
            let tool = json["tool_name"] as? String ?? "a tool"
            let input = json["tool_input"] as? [String: Any] ?? [:]
            let detail = (input["command"] as? String)
                ?? (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? (input["url"] as? String) ?? (input["pattern"] as? String) ?? ""
            let item = Request(project: project, tool: tool, detail: detail)
            pending.append(item)
            waiting[item.id] = connection
            onRequest?()
            // Unanswered: the hook returns nothing and Claude Code asks in the terminal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 110) { [weak self] in
                MainActor.assumeIsolated { self?.answer(item, allow: nil) }
            }
        default:
            Self.reply(connection, body: "")
        }
    }

    private func update(_ id: String, _ project: String, _ state: Session.State) {
        if let i = sessions.firstIndex(where: { $0.id == id }) {
            sessions[i].state = state
            sessions[i].project = project
            sessions[i].updated = Date()
        } else {
            sessions.insert(Session(id: id, project: project, state: state, updated: Date()), at: 0)
        }
        sessions = Array(sessions.filter { Date().timeIntervalSince($0.updated) < 6 * 3600 }.prefix(8))
    }

    // MARK: Hooks in ~/.claude/settings.json

    nonisolated private static let marker = "beanotch-hook"
    private static let markers = [marker, "beanie-hook", "brow-hook"]

    private static func command(timeout: Int) -> String {
        let token = "\"$HOME/Library/Application Support/Beanotch/hook-token\""
        return "[ -n \"$BEANOTCH_SELF\" ] && exit 0; curl -s -m \(timeout) -H \"X-Beanotch-Token: $(cat \(token) 2>/dev/null)\" "
            + "--data-binary @- http://127.0.0.1:\(port)/\(marker) 2>/dev/null; exit 0"
    }

    private static let events: [(String, Int)] = [("PermissionRequest", 115), ("UserPromptSubmit", 3), ("Stop", 3), ("Notification", 3)]

    private static func readSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private static func writeSettings(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: settingsURL, options: .atomic)
    }

    static func hooksInstalled(_ markers: [String] = [marker]) -> Bool {
        let hooks = readSettings()["hooks"] as? [String: Any] ?? [:]
        return hooks.values.contains { groups in
            (groups as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { isOurs($0, markers) }
            }
        }
    }

    private static func isOurs(_ hook: [String: Any], _ markers: [String]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return markers.contains { command.contains($0) }
    }

    // Adds Beanotch's entries next to whatever is there; the original is kept once as settings.json.beanotch-backup.
    private static func installHooks() {
        let backup = settingsURL.appendingPathExtension("beanotch-backup")
        if FileManager.default.fileExists(atPath: settingsURL.path), !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        var json = readSettings()
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command(timeout: timeout), "timeout": timeout + 5]]])
            hooks[event] = groups
        }
        json["hooks"] = hooks
        writeSettings(json)
    }

    private static func removeHooks() {
        var json = readSettings()
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            let kept = (value as? [[String: Any]] ?? []).compactMap { group -> [String: Any]? in
                var group = group
                let commands = (group["hooks"] as? [[String: Any]] ?? []).filter { !isOurs($0, markers) }
                if commands.isEmpty { return nil }
                group["hooks"] = commands
                return group
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        json["hooks"] = hooks.isEmpty ? nil : hooks
        writeSettings(json)
    }
}
