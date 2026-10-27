import AppKit
import Network

// Long terminal commands in the notch: `beanotch run npm run build` shows the command while it runs and turns green
// or red when it ends. The command-line tool is a small shell script that posts to 127.0.0.1 here, with the same kind
// of private token file as the Claude bridge so web pages can't post.
@MainActor
final class DevRuns: ObservableObject {
    struct Run: Identifiable, Equatable {
        let id: String
        let name: String
        let folder: String
        let started: Date
    }

    static let port: UInt16 = 47824

    @Published private(set) var running: [Run] = []
    @Published private(set) var installedAt: String?
    var onNotice: ((Notice) -> Void)?
    private var listener: NWListener?

    var current: Run? { running.last }

    private static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Beanotch")
    }
    private static var tokenURL: URL { supportFolder.appendingPathComponent("run-token") }

    private lazy var token: String = {
        if let saved = try? String(contentsOf: Self.tokenURL, encoding: .utf8), saved.count >= 32 { return saved }
        let fresh = (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
        try? FileManager.default.createDirectory(at: Self.supportFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.tokenURL.path, contents: Data(fresh.utf8), attributes: [.posixPermissions: 0o600])
        return fresh
    }()

    init() {
        installedAt = Self.places.first { FileManager.default.fileExists(atPath: $0 + "/beanotch") }
    }

    func start() {
        guard listener == nil else { return }
        _ = token
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { return }
        weak let runs = self
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            ClaudeBridge.receive(connection, buffer: Data()) { request in
                MainActor.assumeIsolated { runs?.handle(request) }
                ClaudeBridge.reply(connection, body: "")
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func handle(_ request: ClaudeBridge.HTTPRequest) {
        guard request.token == token,
              let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
              let id = json["id"], let name = json["name"] else { return }
        let folder = URL(fileURLWithPath: json["cwd"] ?? "").lastPathComponent
        if json["state"] == "start" {
            running.removeAll { $0.id == id }
            running.append(Run(id: id, name: Self.short(name), folder: folder, started: Date()))
            return
        }
        guard let run = running.first(where: { $0.id == id }) else { return }
        running.removeAll { $0.id == id }
        let ok = json["code"] == "0"
        let took = Self.duration(Date().timeIntervalSince(run.started))
        if !ok { NSSound(named: "Basso")?.play() }
        onNotice?(Notice(icon: ok ? "checkmark.circle.fill" : "xmark.octagon.fill", color: ok ? Theme.good : Theme.red,
                         left: ok ? "Done · \(took)" : "Failed · exit \(json["code"] ?? "?")", right: run.name,
                         duration: ok ? 5 : 10, essential: true))
    }

    // "npm run build" rather than "/usr/local/bin/npm run build --verbose …".
    private static func short(_ command: String) -> String {
        var words = command.split(separator: " ").map(String.init)
        if let first = words.first { words[0] = URL(fileURLWithPath: first).lastPathComponent }
        let text = words.joined(separator: " ")
        return text.count > 40 ? String(text.prefix(39)) + "…" : text
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3600)h \(s % 3600 / 60)m"
    }

    // MARK: The command-line tool

    // Folders already on the PATH that this user can write to, Homebrew's first.
    private static let places = ["/opt/homebrew/bin", "/usr/local/bin",
                                 FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]

    static let script = """
    #!/bin/sh
    # beanotch run <command…>: shows the command in the Mac's notch while it runs, and whether it worked.
    [ "$1" = run ] && shift
    [ $# -eq 0 ] && { echo "usage: beanotch run <command…>"; exit 2; }
    token=$(cat "$HOME/Library/Application Support/Beanotch/run-token" 2>/dev/null)
    id="$$-$(date +%s)"
    post() {
      curl -s -m 1 -H "X-Beanotch-Token: $token" -H "Content-Type: application/json" \\
        --data-binary "$1" http://127.0.0.1:\(port)/run >/dev/null 2>&1
    }
    esc() { printf '%s' "$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'; }
    name=$(esc "$*")
    cwd=$(esc "$PWD")
    post "{\\"id\\":\\"$id\\",\\"name\\":\\"$name\\",\\"cwd\\":\\"$cwd\\",\\"state\\":\\"start\\"}"
    "$@"
    code=$?
    post "{\\"id\\":\\"$id\\",\\"name\\":\\"$name\\",\\"state\\":\\"end\\",\\"code\\":\\"$code\\"}"
    exit $code
    """

    // Puts `beanotch` in the first writable folder on the PATH. Returns where, or nil.
    @discardableResult
    func install() -> String? {
        _ = token
        let fm = FileManager.default
        for place in Self.places {
            if place.hasSuffix(".local/bin") { try? fm.createDirectory(atPath: place, withIntermediateDirectories: true) }
            guard fm.isWritableFile(atPath: place) else { continue }
            let path = place + "/beanotch"
            guard (try? Self.script.write(toFile: path, atomically: true, encoding: .utf8)) != nil else { continue }
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            installedAt = place
            return place
        }
        return nil
    }

    func uninstall() {
        for place in Self.places { try? FileManager.default.removeItem(atPath: place + "/beanotch") }
        installedAt = nil
    }
}
