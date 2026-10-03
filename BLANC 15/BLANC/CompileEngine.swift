//
//  CompileEngine.swift
//  BLANC
//
//  Shells out to a locally installed TeX distribution (pdflatex / xelatex).
//  Debounced so a burst of keystrokes triggers exactly one compile, keeping
//  CPU and battery usage low during real-time editing.
//

import Foundation
import AppKit
import Combine

enum CompileStatus: Equatable {
    case idle
    case compiling
    case success(pdfURL: URL, seconds: Double)
    case failure(log: String)
}

struct TeXLogEntry: Identifiable, Equatable {
    enum Kind { case error, warning }
    let id = UUID()
    let kind: Kind
    let file: String
    let line: Int?
    let message: String
}

@MainActor
final class CompileEngine: ObservableObject {
    @Published var isCompiling: Bool = false
    @Published var logs: [String] = []
    var configPath: String? = nil
    
    @Published private(set) var status: CompileStatus = .idle
    @Published private(set) var lastLog: String = ""
    /// Structured diagnostics parsed from the last compile, newest first —
    /// backs the error/warning badges and the inline line highlighting.
    @Published private(set) var diagnostics: [TeXLogEntry] = []
    
    var errorCount: Int { diagnostics.filter { $0.kind == .error }.count }
    var warningCount: Int { diagnostics.filter { $0.kind == .warning }.count }

    /// Time to wait after the last keystroke before compiling.
    private let debounceInterval: UInt64 = 700_000_000 // 700ms in nanoseconds
    private var debounceTask: Task<Void, Never>?
    private var pendingRecompile = false

    /// Well-known install locations, checked in order, since TeX Live rarely
    /// ends up on the GUI-app PATH on macOS.
private let searchPaths = [
        "/Library/TeX/texbin",
        "/usr/local/texlive/2026/bin/universal-darwin",
        "/usr/local/texlive/2025/bin/universal-darwin",
        "/usr/local/texlive/2026basic/bin/universal-darwin",
        "/usr/local/texlive/2025basic/bin/universal-darwin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

func resolveBinary(_ name: String) -> String? {
        let fm = FileManager.default
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

var isAnyEngineAvailable: Bool {
        resolveBinary("pdflatex") != nil || resolveBinary("xelatex") != nil
    }

    /// Call on every text change. Coalesces rapid edits into a single compile.
func scheduleCompile(source: String, engine: TeXEngine, workingDirectory: URL, mainFileName: String) {
    debounceTask?.cancel()
    debounceTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: self?.debounceInterval ?? 700_000_000)
        guard !Task.isCancelled else { return }
        await self?.compileNow(source: source, engine: engine, workingDirectory: workingDirectory, mainFileName: mainFileName)
    }
}
    
    func compileNow(source: String, engine: TeXEngine, workingDirectory: URL, mainFileName: String) async {
        if isCompiling {
            pendingRecompile = true
            return
        }

        isCompiling = true
        status = .compiling
        
        // ctex / xeCJK / fontspec only work with XeLaTeX, so switch automatically
        // when the document needs them, whatever the picker says.
        let usedEngine: TeXEngine = (engine == .pdflatex && Self.needsUnicodeEngine(source)) ? .xelatex : engine

        guard let binary = self.resolveBinary(usedEngine.binaryName) else {
            status = .failure(log: "\(usedEngine.title) was not found. Install TeX Live or MacTeX, then relaunch BLANC.")
            isCompiling = false
            return
        }

        let start = Date()
    do {
        // Persist the buffer first so the compiler sees current content.
        let mainURL = workingDirectory.appendingPathComponent(mainFileName)
        try source.write(to: mainURL, atomically: true, encoding: .utf8)

        // ctex's `fontset=windows` needs SimSun etc., which macOS doesn't have.
        // Compile a throw-away copy using `fontset=mac`; the user's file is untouched.
        var buildSource = source
        if usedEngine == .xelatex {
            buildSource = source.replacingOccurrences(of: #"fontset\s*=\s*windows"#, with: "fontset=mac", options: .regularExpression)
        }
        let useCopy = buildSource != source
        let texURL = useCopy ? workingDirectory.appendingPathComponent(Self.buildCopyName) : mainURL
        if useCopy { try buildSource.write(to: texURL, atomically: true, encoding: .utf8) }

        var compileArgs = [
            "-interaction=nonstopmode",
            "-halt-on-error",
            "-file-line-error",
            "-output-directory=\(workingDirectory.path)",
        ]
        if useCopy { compileArgs.append("-jobname=" + (mainFileName as NSString).deletingPathExtension) }
        compileArgs.append(texURL.path)
        var result = try await runProcess(binary: binary, arguments: compileArgs, workingDirectory: workingDirectory)

        // Self-healing, in this order:
        // 1. "Mismatched LaTeX support files": packages in the per-user tree are newer
        //    than the system LaTeX kernel. Remove the per-user installs (older BLANC
        //    versions put them there), then retry.
        if result.exitCode != 0, Self.isKernelMismatch(result.output) {
            await removeUserInstalls(workingDirectory: workingDirectory)
            result = try await runProcess(binary: binary, arguments: compileArgs, workingDirectory: workingDirectory)
        }
        // 2. Package missing, or the TeX Live itself is out of date: with the user's
        //    consent, update the *system* TeX Live (consistent kernel + formats).
        if result.exitCode != 0, !askedFix,
           Self.isKernelMismatch(result.output) || Self.missingFile(in: result.output) != nil {
            askedFix = true
            let missing = Self.missingFile(in: result.output)
            if confirmFix(missing: missing) {
                status = .compiling
                if await repairTeXLive(missing: missing, workingDirectory: workingDirectory) {
                    result = try await runProcess(binary: binary, arguments: compileArgs, workingDirectory: workingDirectory)
                }
            }
        }
        
        let pdfURL = workingDirectory.appendingPathComponent((mainFileName as NSString).deletingPathExtension + ".pdf")
        let elapsed = Date().timeIntervalSince(start)
        
        diagnostics = Self.parseDiagnostics(from: result.output, mainFileName: mainFileName)
        
        if result.exitCode == 0, FileManager.default.fileExists(atPath: pdfURL.path) {
            status = .success(pdfURL: pdfURL, seconds: elapsed)
            lastLog = result.output
        } else {
            status = .failure(log: extractError(from: result.output))
            lastLog = result.output
        }
    } catch {
        status = .failure(log: error.localizedDescription)
    }

        isCompiling = false
        if pendingRecompile {
            pendingRecompile = false
            scheduleCompile(source: source, engine: engine, workingDirectory: workingDirectory, mainFileName: mainFileName)
        }
    }

    static let buildCopyName = "_blanc_build.tex"

    static func needsUnicodeEngine(_ source: String) -> Bool {
        ["ctex", "xeCJK", "fontspec", "unicode-math", "\\setmainfont", "\\setCJKmainfont"].contains { source.contains($0) }
    }

    /// "File `ctexart.cls' not found" -> "ctexart.cls"
    static func missingFile(in log: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"File `([^']+\.(?:sty|cls|def|cfg|fd|clo|tex))' not found"#),
              let m = re.firstMatch(in: log, range: NSRange(log.startIndex..., in: log)),
              let r = Range(m.range(at: 1), in: log) else { return nil }
        return String(log[r])
    }

    private var askedFix = false

    static func isKernelMismatch(_ log: String) -> Bool {
        log.contains("Mismatched LaTeX support files") || log.contains("You have requested release")
    }

    private func confirmFix(missing: String?) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Your TeX Live needs an update"
        alert.informativeText = (missing.map { "\($0) is not installed. " } ?? "Your LaTeX installation is out of date. ")
            + "BLANC can fix this by updating your system TeX Live and installing what is missing (CJK / ctex included). "
            + "macOS will ask for your password, and it may take a few minutes."
        alert.addButton(withTitle: "Fix Now")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Removes packages that older BLANC builds installed into the per-user tree.
    private func removeUserInstalls(workingDirectory: URL) async {
        guard let tlmgr = resolveBinary("tlmgr"),
              let listed = try? await runProcess(binary: tlmgr, arguments: ["--usermode", "list", "--only-installed"], workingDirectory: workingDirectory) else { return }
        let names = listed.output.components(separatedBy: "\n").compactMap { line -> String? in
            guard line.hasPrefix("i "), let colon = line.firstIndex(of: ":") else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 2)..<colon]).trimmingCharacters(in: .whitespaces)
        }
        guard !names.isEmpty else { return }
        _ = try? await runProcess(binary: tlmgr, arguments: ["--usermode", "remove", "--force"] + names, workingDirectory: workingDirectory)
    }

    /// `tlmgr update --self --all` (+ install the package that ships `missing`) as admin.
    private func repairTeXLive(missing: String?, workingDirectory: URL) async -> Bool {
        guard let tlmgr = resolveBinary("tlmgr") else { return false }
        var packages: [String] = []
        if let missing,
           let found = try? await runProcess(binary: tlmgr, arguments: ["search", "--global", "--file", "/" + missing], workingDirectory: workingDirectory) {
            packages = found.output.components(separatedBy: "\n")
                .filter { $0.hasSuffix(":") && !$0.hasPrefix("\t") && !$0.hasPrefix(" ") }
                .map { String($0.dropLast()) }
        }
        if packages.isEmpty, missing?.hasPrefix("ctex") == true { packages = ["ctex", "xecjk"] }
        let binDir = (tlmgr as NSString).deletingLastPathComponent
        var cmd = "export PATH='\(binDir)':$PATH; '\(tlmgr)' update --self --all"
        if !packages.isEmpty { cmd += "; '\(tlmgr)' install " + packages.joined(separator: " ") }
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
                p.standardOutput = Pipe()
                p.standardError = Pipe()
                do { try p.run(); p.waitUntilExit(); continuation.resume(returning: p.terminationStatus == 0) }
                catch { continuation.resume(returning: false) }
            }
        }
    }

    /// Parses pdflatex/xelatex log output into structured diagnostics.
    /// Handles two common shapes:
    ///   "./main.tex:15: LaTeX Error: File `xcolour.sty' not found."
    ///   "! LaTeX Error: File `xcolour.sty' not found."  (line number found via "l.15" nearby)
static func parseDiagnostics(from log: String, mainFileName: String) -> [TeXLogEntry] {
        var entries: [TeXLogEntry] = []
        let lines = log.components(separatedBy: "\n")

        let filelineError = try! NSRegularExpression(pattern: #"^(.*?):(\d+):\s*(.*)$"#)

        for (idx, raw) in lines.enumerated() {
            let ns = raw as NSString
            if raw.hasPrefix("!") {
                let message = String(raw.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                // Look a few lines ahead for "l.<num>" which pdflatex prints for the offending line.
                var foundLine: Int? = nil
                for lookahead in (idx + 1)..<min(idx + 6, lines.count) {
                    if let match = try? NSRegularExpression(pattern: #"^l\.(\d+)"#).firstMatch(in: lines[lookahead], range: NSRange(lines[lookahead].startIndex..., in: lines[lookahead])),
                       let range = Range(match.range(at: 1), in: lines[lookahead]) {
                        foundLine = Int(lines[lookahead][range])
                        break
                    }
                }
                entries.append(TeXLogEntry(kind: .error, file: mainFileName, line: foundLine, message: message))
            } else if let match = filelineError.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)),
                      let fileRange = Range(match.range(at: 1), in: raw),
                      let lineRange = Range(match.range(at: 2), in: raw),
                      let msgRange = Range(match.range(at: 3), in: raw),
                      let lineNum = Int(raw[lineRange]) {
                // "<file>:<line>: message". The file may be a package (ctex.sty:78: ...),
                // in which case <line> is NOT a line of the user's document.
                let base = (String(raw[fileRange]) as NSString).lastPathComponent
                let isMain = base == mainFileName || base == Self.buildCopyName
                var message = String(raw[msgRange]).trimmingCharacters(in: .whitespaces)
                // Long messages continue on the next line.
                if message.hasSuffix(":"), idx + 1 < lines.count {
                    let next = lines[idx + 1].trimmingCharacters(in: .whitespaces)
                    if !next.isEmpty, !next.hasPrefix("l.") { message += " " + next }
                }
                var line: Int? = isMain ? lineNum : nil
                if !isMain {
                    for lookahead in (idx + 1)..<min(idx + 15, lines.count) {
                        if let m = try? NSRegularExpression(pattern: #"^l\.(\d+)"#).firstMatch(in: lines[lookahead], range: NSRange(lines[lookahead].startIndex..., in: lines[lookahead])),
                           let r = Range(m.range(at: 1), in: lines[lookahead]) {
                            line = Int(lines[lookahead][r])
                            break
                        }
                    }
                }
                entries.append(TeXLogEntry(kind: .error, file: mainFileName, line: line, message: message))
            } else if raw.contains("LaTeX Warning:") {
                let message = raw.components(separatedBy: "LaTeX Warning:").last?.trimmingCharacters(in: .whitespaces) ?? raw
                entries.append(TeXLogEntry(kind: .warning, file: mainFileName, line: nil, message: message))
            }
        }
        return entries
    }

    /// Pulls the most relevant "! " error line out of a noisy log so the user
    /// isn't stuck reading pages of TeX engine chatter.
    private func extractError(from log: String) -> String {
        let lines = log.split(separator: "\n")
        if let errorLine = lines.first(where: { $0.hasPrefix("!") }) {
            let idx = lines.firstIndex(of: errorLine) ?? 0
            let context = lines[idx..<min(idx + 5, lines.count)].joined(separator: "\n")
            return context
        }
        return log.isEmpty ? "Compilation failed with no output." : String(log.suffix(2000))
    }

    /// Thread-safe buffer so the pipe's readability handler (background queue)
    /// and the termination handler can share collected output safely.
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        func snapshot() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }

    private struct ProcessResult {
        let exitCode: Int32
        let output: String
    }

    private func runProcess(binary: String, arguments: [String], workingDirectory: URL) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            // GUI apps get a minimal PATH; tlmgr/kpsewhich/xdvipdfmx must be reachable.
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (binary as NSString).deletingLastPathComponent + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            process.environment = env

            // Keep the compiler niced down so real-time compilation on every
            // keystroke doesn't compete with UI responsiveness.
            process.qualityOfService = .utility

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            let handle = pipe.fileHandleForReading
            let collected = DataBox()
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty {
                    fh.readabilityHandler = nil
                } else {
                    collected.append(chunk)
                }
            }

            process.terminationHandler = { proc in
                handle.readabilityHandler = nil
                let output = String(data: collected.snapshot(), encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessResult(exitCode: proc.terminationStatus, output: output))
            }
        }
    }
}
