import FlyingFox
import Foundation
import SwiftUI
import Network

/// 上传的文本文件模型
struct UploadedTextFile: Identifiable, Hashable {
    let id: URL
    let fileName: String
    let fileSize: Int64
    let createdAt: Date
}

/// Web 上传服务管理
@MainActor
final class WebUploadServer: ObservableObject {
    static let shared = WebUploadServer()
    static let webPort = 8088

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var serverURL: URL?
    @Published private(set) var uploadedFiles: [UploadedTextFile] = []
    @Published private(set) var unavailableReason: String?

    private let uploadsDirectoryURL: URL
    private var server: HTTPServer?
    private var serverTask: Task<Void, Never>?
    private var bonjourService: NetService?
    private var permissionBrowser: NWBrowser?

    private init() {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        uploadsDirectoryURL = docs.appendingPathComponent(
            "Uploads",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: uploadsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Public API
    func start() async {
        guard !isRunning else { return }
        unavailableReason = nil

        // 触发“本地网络”权限弹窗（iOS 14+）。仅浏览几秒后自动停止。
        triggerLocalNetworkPermission()

        let httpServer = HTTPServer(port: UInt16(WebUploadServer.webPort))

        // GET /
        await httpServer.appendRoute("GET /") { [weak self] _ in
            guard let self else { return HTTPResponse(statusCode: .ok) }
            let html = await self.renderUploadHTML()
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                body: Data(html.utf8)
            )
        }

        // POST /upload/:name  body = file bytes
        await httpServer.appendRoute("POST /upload/:name") {
            [weak self] request in
            guard let self else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            guard let name = request.routeParameters["name"], !name.isEmpty
            else {
                return HTTPResponse(statusCode: .badRequest)
            }
            let safeName = name.replacingOccurrences(of: "/", with: "_")
            let destURL = await self.uniqueDestinationURL(fileName: safeName)

            let data = try await request.bodyData

            do {
                try data.write(to: destURL, options: .atomic)
                DispatchQueue.main.async { self.refreshUploadedFiles() }
                return HTTPResponse(statusCode: .created)
            } catch {
                return HTTPResponse(
                    statusCode: .internalServerError,
                    headers: [.contentType: "text/plain; charset=utf-8"],
                    body: Data(
                        String(
                            format: String(
                                localized: "import.web.srv_save_failed"
                            ),
                            error.localizedDescription
                        ).utf8
                    )
                )
            }
        }

        // GET /files/:name  下载文件
        await httpServer.appendRoute("GET /files/:name") {
            [weak self] request in
            guard let self else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            guard let name = request.routeParameters["name"], !name.isEmpty
            else {
                return HTTPResponse(statusCode: .badRequest)
            }
            let fileURL = self.uploadsDirectoryURL.appendingPathComponent(
                name
            )
            guard FileManager.default.fileExists(atPath: fileURL.path)
            else {
                return HTTPResponse(statusCode: .notFound)
            }
            do {
                let data = try Data(contentsOf: fileURL)
                return HTTPResponse(
                    statusCode: .ok,
                    headers: [.contentType: "text/plain; charset=utf-8"],
                    body: data
                )
            } catch {
                return HTTPResponse(statusCode: .internalServerError)
            }
        }

        server = httpServer
        serverTask = Task { [weak self] in
            do {
                try await httpServer.run()
            } catch {
                // 如果是主动停止导致的取消，不应视为错误
                if (error is CancellationError) || Task.isCancelled {
                    // no-op
                } else {
                    DispatchQueue.main.async {
                        self?.unavailableReason = String(
                            format: String(
                                localized: "import.web.srv_run_failed"
                            ),
                            error.localizedDescription
                        )
                        self?.isRunning = false
                        self?.serverURL = nil
                    }
                }
            }
        }

        isRunning = true
        if let ip = Self.currentWiFiIPv4Address() {
            serverURL = URL(string: "http://\(ip):\(WebUploadServer.webPort)/")
        } else {
            serverURL = URL(
                string: String(
                    format: String(localized: "import.web.srv_url"),
                    WebUploadServer.webPort
                )
            )
        }
        refreshUploadedFiles()
        startBonjour()
    }

    func stop() async {
        stopBonjour()
        await server?.stop()
        server = nil
        serverTask?.cancel()
        serverTask = nil
        isRunning = false
        serverURL = nil
        unavailableReason = nil
    }

    func refreshUploadedFiles() {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: uploadsDirectoryURL,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        let mapped: [UploadedTextFile] = urls.compactMap { url in
            guard
                url.pathExtension.lowercased() == "txt"
                    || url.pathExtension.lowercased() == "text"
            else { return nil }
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .creationDateKey,
            ])
            let size = Int64(values?.fileSize ?? 0)
            let created = values?.creationDate ?? Date()
            return UploadedTextFile(
                id: url,
                fileName: url.lastPathComponent,
                fileSize: size,
                createdAt: created
            )
        }.sorted { $0.createdAt > $1.createdAt }
        DispatchQueue.main.async {
            self.uploadedFiles = mapped
        }
    }

    func delete(file: UploadedTextFile) throws {
        try FileManager.default.removeItem(at: file.id)
        refreshUploadedFiles()
    }

    func uploadsDirectory() -> URL { uploadsDirectoryURL }

    // MARK: - Helpers
    private func startBonjour() {
        stopBonjour()
        let service = NetService(
            domain: "local.",
            type: "_http._tcp.",
            name: "BookReader Upload",
            port: Int32(Self.webPort)
        )
        service.includesPeerToPeer = true
        service.publish()
        bonjourService = service
    }

    private func stopBonjour() {
        bonjourService?.stop()
        bonjourService = nil
    }

    /// 通过 NWBrowser 浏览 Bonjour 服务以触发本地网络权限弹窗
    private func triggerLocalNetworkPermission() {
        // 若已触发过或正在进行，避免重复
        if permissionBrowser != nil { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_http._tcp", domain: nil),
            using: params
        )
        permissionBrowser = browser
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready, .failed(_), .cancelled:
                // 就绪或失败/取消后，稍等片刻再关闭，避免频繁重建
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.permissionBrowser?.cancel()
                    self?.permissionBrowser = nil
                }
            default:
                break
            }
        }
        browser.start(queue: .main)
        // 兜底：最多浏览 6 秒
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.permissionBrowser?.cancel()
            self?.permissionBrowser = nil
        }
    }

    private func uniqueDestinationURL(fileName: String) -> URL {
        var candidate = uploadsDirectoryURL.appendingPathComponent(fileName)
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = "\(name)-\(index).\(ext.isEmpty ? "txt" : ext)"
            candidate = uploadsDirectoryURL.appendingPathComponent(newName)
            index += 1
        }
        return candidate
    }

    private func renderUploadHTML() -> String {
        let title = String(localized: "import.html.title")
        let hint = String(localized: "import.html.hint")
        let btnText = String(localized: "import.html.btn.upload")
        let msgUploading = String(localized: "import.html.msg_uploading")
        let msgSuccess = String(localized: "import.html.msg_success")
        let msgFailed = String(localized: "import.html.msg_failed")
        let msgException = String(localized: "import.html.msg_exception")
        let msgChooseFile = String(localized: "import.html.msg_choose_file")

        return """
            <!doctype html>
            <html>
            <head>
              <meta name=viewport content="width=device-width, initial-scale=1">
              <title>\(title)</title>
              <style>
                body{ font-family:-apple-system,system-ui,Segoe UI,Roboto,Helvetica,Arial; padding:24px; }
                .card{ max-width:560px; margin:auto; padding:20px; border:1px solid #ddd; border-radius:12px; }
                h1{ font-size:20px; margin:0 0 12px; }
                p{ color:#555; }
                input[type=file]{ margin:12px 0; }
                button{ padding:10px 14px; border-radius:8px; border:0; background:#007aff; color:white; }
                .msg{ margin-top:12px; color:#555; }
              </style>
            </head>
            <body>
              <div class="card">
                <h1>\(title)</h1>
                <p>\(hint)</p>
                <input id=file type=file accept=".txt,.text" />
                <div>
                  <button id=btn>\(btnText)</button>
                </div>
                <div class=msg id=msg></div>
              </div>
              <script>
              const $ = (s)=>document.querySelector(s);
              $('#btn').addEventListener('click', async ()=>{
                const f = $('#file').files[0];
                if(!f){ $('#msg').textContent = '\(msgChooseFile)'; return; }
                $('#msg').textContent = '\(msgUploading)';
                try{
                  const name = encodeURIComponent(f.name);
                  const resp = await fetch(`/upload/${name}`, { method: 'POST', body: f });
                  if(resp.ok){ $('#msg').textContent = '\(msgSuccess)'; }
                  else{ $('#msg').textContent = '\(msgFailed) ' + resp.status; }
                }catch(e){ $('#msg').textContent = '\(msgException) ' + e; }
              });
              </script>
            </body>
            </html>
            """
    }

    // 获取 Wi-Fi IPv4 地址
    private static func currentWiFiIPv4Address() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return nil
        }
        defer { freeifaddrs(ifaddrPtr) }

        struct Candidate {
            let name: String
            let ip: String
        }

        var preferred: [Candidate] = []
        var backup: [Candidate] = []

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0 else { continue }

            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var a = addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                &a,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }

            let ip = String(cString: hostname)
            // 排除链路本地 169.254.x.x
            guard !ip.hasPrefix("169.254.") else { continue }

            let candidate = Candidate(name: name, ip: ip)
            if name == "en0" { preferred.append(candidate) } else { backup.append(candidate) }
        }

        if let first = preferred.first { return first.ip }
        if let first = backup.first { return first.ip }
        return nil
    }
}
