import SwiftUI
import WebKit
import UniformTypeIdentifiers

let enhanceURL = URL(string: "https://podcast.adobe.com/enhance")!
let audioExts: Set<String> = ["mp3", "wav", "m4a", "flac", "aac", "ogg", "mp4", "mov", "aiff"]

enum DLState { case none, started, finished, failed }

final class Runner: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let webView: WKWebView
    @Published var inputDir: URL?
    @Published var outputDir: URL?
    @Published var logLines: [String] = []
    @Published var running = false
    @Published var status = "Idle. Log in to Adobe in the window below, pick folders, then Start."

    private var task: Task<Void, Never>?
    private var pendingFile: URL?
    private var panelUsed = false
    private var dlState: DLState = .none
    private var currentStem = ""

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        cfg.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: enhanceURL))
    }

    // MARK: logging / helpers
    func log(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(s)"
        DispatchQueue.main.async { self.logLines.insert(line, at: 0) }
    }
    func setStatus(_ s: String) { DispatchQueue.main.async { self.status = s } }

    func js(_ script: String) async -> Any? {
        await withCheckedContinuation { (c: CheckedContinuation<Any?, Never>) in
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(script) { result, _ in c.resume(returning: result) }
            }
        }
    }
    func sleep(_ sec: Double) async { try? await Task.sleep(nanoseconds: UInt64(sec * 1_000_000_000)) }

    func clickButton(_ pattern: String) async -> String {
        let s = #"""
        (function(){
          const re = /\#(pattern)/i;
          const els = [...document.querySelectorAll('button,a,[role=button],label,div[tabindex]')];
          for (const e of els) {
            const t = ((e.innerText || '') + ' ' + (e.getAttribute('aria-label') || '')).trim();
            if (!t || t.length > 60) continue;
            if (!re.test(t)) continue;
            if (/\bapp\b|plugin|extension/i.test(t)) continue;
            const r = e.getBoundingClientRect();
            if (r.width === 0 || r.height === 0) continue;
            if (e.disabled || e.getAttribute('aria-disabled') === 'true') continue;
            e.click();
            return t;
          }
          return '';
        })()
        """#
        return (await js(s) as? String) ?? ""
    }

    func pageLimitMessage() async -> String {
        let s = #"""
        (function(){
          const m = document.body.innerText.match(/(reached[^.\n]{0,40}limit|exceed[^.\n]{0,40}limit|too (long|large)[^.\n]{0,60}|try again (tomorrow|later)[^.\n]{0,30})/i);
          return m ? m[0] : '';
        })()
        """#
        return (await js(s) as? String) ?? ""
    }

    func hasFileInput() async -> Bool {
        (await js("document.querySelectorAll('input[type=file]').length") as? Int ?? 0) > 0
    }

    // Clicks the real "Choose files" button (exact text), never random "Select..." menus
    func clickUpload() async -> String {
        let s = #"""
        (function(){
          const pats = [/^\s*choose files?\s*$/i, /^\s*(upload|browse)( files?)?\s*$/i];
          const els = [...document.querySelectorAll('button,a,[role=button],label,div[tabindex]')];
          for (const re of pats) {
            for (const e of els) {
              const t = (e.innerText || '').trim();
              if (!t || t.length > 40 || !re.test(t)) continue;
              const r = e.getBoundingClientRect();
              if (r.width === 0 || r.height === 0) continue;
              if (e.disabled || e.getAttribute('aria-disabled') === 'true') continue;
              e.click();
              return t;
            }
          }
          return '';
        })()
        """#
        return (await js(s) as? String) ?? ""
    }

    // For diagnostics when upload fails: what buttons does the page actually show?
    func visibleButtons() async -> String {
        let s = #"""
        (function(){
          return [...document.querySelectorAll('button,a,[role=button]')]
            .filter(e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; })
            .map(e => (e.innerText || e.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' '))
            .filter(t => t && t.length < 40)
            .slice(0, 25).join(' | ');
        })()
        """#
        return (await js(s) as? String) ?? ""
    }

    // Keeps trying to hit "Choose files" until the page hands the file chooser to us
    func tryUpload(_ f: URL) async -> Bool {
        var lastClick = Date.distantPast
        var clickedOnce = false
        for i in 0..<45 {
            if Task.isCancelled { return false }
            if panelUsed { return true }
            if Date().timeIntervalSince(lastClick) > 4 {
                let clicked = await clickUpload()
                if !clicked.isEmpty {
                    log("Clicked: \(clicked)")
                    clickedOnce = true
                    lastClick = Date()
                    await sleep(1.5)
                    if panelUsed { return true }
                }
            }
            if !clickedOnce && i >= 12 {
                if await hasFileInput() {
                    log("No button found, injecting file directly")
                    if await inject(f) { return true }
                }
            }
            await sleep(2)
        }
        return false
    }

    func loadPage() async {
        DispatchQueue.main.async { self.webView.load(URLRequest(url: enhanceURL)) }
        await sleep(2)
        for _ in 0..<30 {
            let loading = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                DispatchQueue.main.async { c.resume(returning: self.webView.isLoading) }
            }
            if !loading { break }
            await sleep(1)
        }
        await sleep(3)
    }

    // Push the file into the page's <input type=file> in chunks
    func inject(_ url: URL) async -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        _ = await js("window.__c = [];")
        while true {
            let data = fh.readData(ofLength: 3 * 1024 * 1024)
            if data.isEmpty { break }
            let b64 = data.base64EncodedString()
            _ = await js("window.__c.push(Uint8Array.from(atob('\(b64)'), c => c.charCodeAt(0)));")
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "audio/mpeg"
        let name = url.lastPathComponent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function(){
          const inp = [...document.querySelectorAll('input[type=file]')][0];
          if (!inp) return 'noinput';
          const f = new File(window.__c, '\(name)', {type: '\(mime)'});
          const dt = new DataTransfer(); dt.items.add(f);
          inp.files = dt.files;
          inp.dispatchEvent(new Event('input', {bubbles: true}));
          inp.dispatchEvent(new Event('change', {bubbles: true}));
          window.__c = null;
          return 'ok';
        })()
        """
        return (await js(script) as? String) == "ok"
    }

    // MARK: main loop
    func start() {
        guard let inDir = inputDir, let outDir = outputDir else { return }
        running = true
        task = Task.detached { [self] in
            await runAll(inDir, outDir)
            DispatchQueue.main.async { self.running = false }
        }
    }
    func stop() {
        task?.cancel()
        log("Stopping after current step...")
    }

    func runAll(_ inDir: URL, _ outDir: URL) async {
        let fm = FileManager.default
        let all = ((try? fm.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { audioExts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        log("Found \(all.count) audio file(s).")
        var ok = 0, failed: [String] = [], skipped = 0
        for (i, f) in all.enumerated() {
            if Task.isCancelled { break }
            let stem = f.deletingPathExtension().lastPathComponent
            let existing = (try? fm.contentsOfDirectory(atPath: outDir.path)) ?? []
            if existing.contains(where: { $0.hasPrefix(stem + "_enhanced") }) {
                log("Skip (already done): \(f.lastPathComponent)")
                skipped += 1
                continue
            }
            setStatus("File \(i + 1)/\(all.count): \(f.lastPathComponent)")
            log("Start: \(f.lastPathComponent)")
            if await process(f) {
                ok += 1
                log("Done: \(f.lastPathComponent)")
            } else {
                failed.append(f.lastPathComponent)
                log("FAILED: \(f.lastPathComponent)")
            }
            await sleep(2)
        }
        let summary = "Finished. OK: \(ok), skipped: \(skipped), failed: \(failed.count)"
        log(summary)
        if !failed.isEmpty { log("Failed files: " + failed.joined(separator: ", ")) }
        setStatus(summary)
    }

    func process(_ f: URL) async -> Bool {
        currentStem = f.deletingPathExtension().lastPathComponent
        dlState = .none
        pendingFile = f

        var uploaded = false
        for attempt in 1...3 {
            if Task.isCancelled { return false }
            panelUsed = false
            if attempt > 1 { log("Retrying upload (attempt \(attempt)/3)...") }
            await loadPage()
            uploaded = await tryUpload(f)
            if uploaded { break }
            let btns = await visibleButtons()
            log("Upload not possible. Buttons on page: " + btns)
        }
        if !uploaded {
            log("Could not upload after 3 attempts. Are you logged in and on the Enhance page?")
            return false
        }
        log("File handed to page, waiting for processing...")

        let begin = Date()
        var lastClick = Date.distantPast
        while Date().timeIntervalSince(begin) < 25 * 60 {
            if Task.isCancelled { return false }
            if dlState == .finished { return true }
            if dlState == .failed { return false }
            if dlState == .none {
                let limit = await pageLimitMessage()
                if !limit.isEmpty {
                    log("Page says: \(limit)")
                    return false
                }
                if Date().timeIntervalSince(lastClick) > 6 {
                    let clicked = await clickButton("download")
                    if !clicked.isEmpty {
                        log("Clicked: \(clicked)")
                        lastClick = Date()
                    }
                }
            }
            await sleep(2)
        }
        log("Timed out waiting for the result.")
        return false
    }

    // MARK: WKUIDelegate
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        if running, let f = pendingFile {
            panelUsed = true
            completionHandler([f])
        } else {
            let p = NSOpenPanel()
            p.allowsMultipleSelection = parameters.allowsMultipleSelection
            completionHandler(p.runModal() == .OK ? p.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let mime = navigationResponse.response.mimeType ?? ""
        if !navigationResponse.canShowMIMEType || mime.hasPrefix("audio/") || mime.hasPrefix("video/") {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: WKDownloadDelegate
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let out = outputDir else { completionHandler(nil); return }
        let ext = (suggestedFilename as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        let base = (running ? currentStem : (suggestedFilename as NSString).deletingPathExtension) + (running ? "_enhanced" : "")
        var dest = out.appendingPathComponent(base + suffix)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = out.appendingPathComponent("\(base)-\(n)\(suffix)")
            n += 1
        }
        dlState = .started
        log("Downloading to \(dest.lastPathComponent)")
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        dlState = .finished
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        dlState = .failed
        log("Download error: \(error.localizedDescription)")
    }
}

struct WebContainer: NSViewRepresentable {
    let wv: WKWebView
    func makeNSView(context: Context) -> WKWebView { wv }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

func pickFolder(_ title: String) -> URL? {
    let p = NSOpenPanel()
    p.title = title
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.canCreateDirectories = true
    return p.runModal() == .OK ? p.url : nil
}

struct ContentView: View {
    @StateObject var r = Runner()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("Input folder…") { if let u = pickFolder("Choose input folder") { r.inputDir = u } }
                Text(r.inputDir?.path ?? "not set").lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .leading)
                Button("Output folder…") { if let u = pickFolder("Choose output folder") { r.outputDir = u } }
                Text(r.outputDir?.path ?? "not set").lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .leading)
                Spacer()
                Button("Reload page") { r.webView.load(URLRequest(url: enhanceURL)) }.disabled(r.running)
                if r.running {
                    Button("Stop") { r.stop() }
                } else {
                    Button("Start") { r.start() }
                        .disabled(r.inputDir == nil || r.outputDir == nil)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(8)
            Text(r.status).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.bottom, 6)
            Divider()
            WebContainer(wv: r.webView)
            Divider()
            ScrollView {
                Text(r.logLines.prefix(300).joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(6)
            }
            .frame(height: 140)
        }
    }
}

@main
struct AudioBatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().frame(minWidth: 1100, minHeight: 800)
        }
    }
}
