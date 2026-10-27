import AppKit
import CoreImage.CIFilterBuiltins
import Network

// Phone and Shelf over the same Wi-Fi, with nothing to install on the phone: while the QR is on screen, a small
// web server takes uploads at a one-time address, and offers what's on the Shelf for download. Uploads land in
// ~/Downloads/Beanotch and on the Shelf.
@MainActor
final class PhoneDrop: ObservableObject {
    @Published private(set) var address: URL?
    @Published private(set) var qr: NSImage?
    @Published private(set) var received = 0
    @Published private(set) var problem: String?
    var onFile: ((URL) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "beanotch.phonedrop")
    private let shelf = Offered()

    // The Shelf's files, for the phone to download; read on the server's queue.
    var offered: [URL] {
        get { shelf.urls }
        set { shelf.urls = newValue }
    }

    var running: Bool { listener != nil }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/Beanotch")
    }

    func start() {
        guard listener == nil else { return }
        guard let ip = Self.localAddress() else {
            problem = "Connect this Mac to Wi-Fi first"
            return
        }
        problem = nil
        received = 0
        let token = String((0..<16).map { _ in "abcdefghijkmnpqrstuvwxyz23456789".randomElement()! })
        guard let listener = try? NWListener(using: .tcp, on: .any) else {
            problem = "Couldn't start the receiver"
            return
        }
        let folder = Self.folder, offered = shelf
        listener.newConnectionHandler = { [weak self] connection in
            DropConnection(connection: connection, token: token, folder: folder, offered: offered, queue: self?.queue ?? .main) { url in
                Task { @MainActor in
                    self?.received += 1
                    self?.onFile?(url)
                }
            }.start()
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    guard let port = self?.listener?.port else { return }
                    let url = URL(string: "http://\(ip):\(port.rawValue)/\(token)")!
                    self?.address = url
                    self?.qr = Self.qrImage(url.absoluteString)
                case .failed:
                    self?.problem = "The receiver stopped"
                    self?.stop()
                default: break
                }
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        address = nil
        qr = nil
    }

    private static func qrImage(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width / 2, height: output.extent.height / 2))
    }

    // The Mac's IPv4 address on Wi-Fi or Ethernet.
    private static func localAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: [String: String] = [:]
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if !ip.hasPrefix("127.") { found[name] = ip }
        }
        return found["en0"] ?? found["en1"] ?? found.values.first
    }
}

final class Offered: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [URL] = []
    var urls: [URL] {
        get { lock.withLock { list } }
        set { lock.withLock { list = newValue } }
    }
}

// One HTTP request: the page, the Shelf's list, one Shelf file sent down, or one upload's bytes streamed to disk.
// Just enough HTTP for a phone's browser.
private final class DropConnection {
    private let connection: NWConnection
    private let token: String
    private let folder: URL
    private let offered: Offered
    private let queue: DispatchQueue
    private let done: (URL) -> Void
    private var head = Data()
    private var file: FileHandle?
    private var fileURL: URL?
    private var remaining = 0

    init(connection: NWConnection, token: String, folder: URL, offered: Offered, queue: DispatchQueue, done: @escaping (URL) -> Void) {
        self.connection = connection
        self.token = token
        self.folder = folder
        self.offered = offered
        self.queue = queue
        self.done = done
    }

    func start() {
        connection.start(queue: queue)
        readHead()
    }

    private func readHead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            if let data { head.append(data) }
            if let end = head.range(of: Data("\r\n\r\n".utf8)) {
                let text = String(decoding: head[..<end.lowerBound], as: UTF8.self)
                route(text, rest: Data(head[end.upperBound...]))
            } else if complete || error != nil || head.count > 32_768 {
                connection.cancel()
            } else {
                readHead()
            }
        }
    }

    private func route(_ text: String, rest: Data) {
        let lines = text.components(separatedBy: "\r\n")
        let request = lines.first?.split(separator: " ").map(String.init) ?? []
        guard request.count >= 2, let components = URLComponents(string: request[1]) else { return respond(400, "Bad request") }
        let headers = Dictionary(lines.dropFirst().compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (line[..<colon].lowercased(), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }, uniquingKeysWith: { a, _ in a })

        switch (request[0], components.path) {
        case ("GET", "/\(token)"):
            respond(200, Self.page, type: "text/html; charset=utf-8")
        case ("GET", "/\(token)/files"):
            let list = offered.urls.enumerated().map { i, url -> [String: Any] in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return ["i": i, "name": url.lastPathComponent, "size": size]
            }
            let json = (try? JSONSerialization.data(withJSONObject: list)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
            respond(200, json, type: "application/json")
        case ("GET", let path) where path.hasPrefix("/\(token)/file/"):
            let urls = offered.urls
            guard let i = Int(path.dropFirst("/\(token)/file/".count)), urls.indices.contains(i) else { return respond(404, "Not found") }
            send(urls[i])
        case ("POST", "/\(token)/upload"):
            let raw = components.queryItems?.first { $0.name == "name" }?.value ?? "file"
            let name = (raw as NSString).lastPathComponent.replacingOccurrences(of: ":", with: "-")
            remaining = Int(headers["content-length"] ?? "") ?? -1
            guard remaining >= 0 else { return respond(411, "Length required") }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = Self.unique(folder.appendingPathComponent(name.isEmpty ? "file" : name))
            FileManager.default.createFile(atPath: url.path, contents: nil)
            fileURL = url
            file = try? FileHandle(forWritingTo: url)
            write(rest)
            readBody()
        default:
            respond(404, "Not found")
        }
    }

    private func write(_ data: Data) {
        guard !data.isEmpty else { return }
        try? file?.write(contentsOf: data.prefix(max(remaining, 0)))
        remaining -= data.count
    }

    private func readBody() {
        guard remaining > 0 else { return finish() }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] data, _, complete, error in
            if let data { write(data) }
            if remaining <= 0 {
                finish()
            } else if complete || error != nil {
                // Cut off half way: don't keep a broken file.
                try? file?.close()
                if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
                connection.cancel()
            } else {
                readBody()
            }
        }
    }

    private func finish() {
        try? file?.close()
        respond(200, "ok")
        if let fileURL { done(fileURL) }
    }

    // A Shelf file, in pieces, as a download. Folders aren't offered.
    private func send(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return respond(404, "Not found") }
        let name = url.lastPathComponent
        let ascii = String(name.map { $0.isASCII && $0 != "\"" ? $0 : "_" })
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ascii
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\n"
            + "Content-Disposition: attachment; filename=\"\(ascii)\"; filename*=UTF-8''\(encoded)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [self] error in
            if error != nil { try? handle.close(); connection.cancel(); return }
            sendChunk(handle)
        })
    }

    private func sendChunk(_ handle: FileHandle) {
        let chunk = (try? handle.read(upToCount: 1 << 20)) ?? Data()
        if chunk.isEmpty {
            try? handle.close()
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { [connection] _ in connection.cancel() })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [self] error in
            if error != nil { try? handle.close(); connection.cancel(); return }
            sendChunk(handle)
        })
    }

    private func respond(_ status: Int, _ body: String, type: String = "text/plain; charset=utf-8") {
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: \(type)\r\n"
            + "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + payload, completion: .contentProcessed { [connection] _ in connection.cancel() })
    }

    private static func unique(_ url: URL) -> URL {
        var candidate = url
        var n = 2
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            n += 1
        }
        return candidate
    }

    private static let page = """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Send to Beanotch</title>
    <style>
    body{margin:0;font:16px -apple-system,system-ui,sans-serif;background:#0b0b0d;color:#fff;display:flex;min-height:100vh;align-items:center;justify-content:center}
    main{width:min(92vw,420px);text-align:center}
    h1{font-size:22px;margin:0 0 6px}p{color:#9a9aa2;margin:0 0 24px}
    label{display:block;padding:28px;border:1.5px dashed #3a3a40;border-radius:18px;cursor:pointer}
    input{display:none}#status{margin-top:18px;color:#5be0bc;min-height:1.4em}
    h2{font-size:15px;margin:28px 0 10px;text-align:left}
    #list a{display:flex;justify-content:space-between;gap:12px;padding:12px 14px;margin-bottom:6px;border-radius:12px;background:#17171b;color:#fff;text-decoration:none;text-align:left}
    #list span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}#list small{color:#9a9aa2;flex:none}
    </style></head><body><main>
    <h1>Send to Beanotch</h1><p>Photos and files go straight to your Mac's Shelf.</p>
    <label>Choose files<input id="f" type="file" multiple></label>
    <div id="status"></div>
    <section id="mac" hidden><h2>On the Mac's Shelf</h2><div id="list"></div></section></main>
    <script>
    const s=document.getElementById('status');
    const size=b=>b<1e6?Math.max(1,Math.round(b/1e3))+' KB':(b/1e6).toFixed(1)+' MB';
    fetch(location.pathname+'/files').then(r=>r.json()).then(files=>{
      if(!files.length)return;
      const list=document.getElementById('list');
      for(const f of files){
        const a=document.createElement('a');a.href=location.pathname+'/file/'+f.i;a.download=f.name;
        const n=document.createElement('span');n.textContent=f.name;
        const z=document.createElement('small');z.textContent=size(f.size);
        a.append(n,z);list.append(a);
      }
      document.getElementById('mac').hidden=false;
    }).catch(()=>{});
    document.getElementById('f').onchange=async e=>{
      const files=[...e.target.files];let n=0;
      for(const f of files){
        s.textContent='Sending '+f.name+' ('+(n+1)+' of '+files.length+')…';
        const r=await fetch(location.pathname+'/upload?name='+encodeURIComponent(f.name),{method:'POST',body:f}).catch(()=>null);
        if(!r||!r.ok){s.textContent='Couldn\\'t send '+f.name;return}
        n++;
      }
      s.textContent=n+' file'+(n==1?'':'s')+' sent ✓';e.target.value='';
    };
    </script></body></html>
    """
}
