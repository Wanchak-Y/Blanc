//
//  EditorView.swift
//  BLANC
//
//  Classic split layout: file tree, LaTeX source, live PDF preview —
//  styled to match the reference mockup (black pill Compile button,
//  red/yellow diagnostic badges, inline error-line tinting).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject private var library: DocumentLibrary
    @StateObject private var engine = CompileEngine()

    let record: ProjectRecord

    @State private var source: String = ""
    @State private var currentEngine: TeXEngine
    @State private var liveCompileEnabled = true
    @State private var showingDiagnosticsPopover = false
    @State private var renamingText: String = ""
    @State private var isRenaming = false
    @State private var folderExpanded = true
    @State private var treeRefresh = 0
    @State private var activeFile: URL
    @State private var expandedFolders: Set<String> = []
    @State private var renameTarget: URL?
    @State private var dropTarget: String?

    init(record: ProjectRecord) {
        self.record = record
        _currentEngine = State(initialValue: record.engine)
        _activeFile = State(initialValue: record.url)
    }

    private var projectDirectory: URL { record.url.deletingLastPathComponent() }
    /// Compilation happens next to whichever file is currently open.
    private var workingDirectory: URL { activeFile.deletingLastPathComponent() }
    private var mainFileName: String { activeFile.lastPathComponent }

    private var errorLinesDict: [Int: String] {
        var dict: [Int: String] = [:]
        for entry in engine.diagnostics where entry.kind == .error {
            if let line = entry.line { dict[line] = entry.message }
        }
        return dict
    }

    var body: some View {
        HSplitView {
            fileTreeSidebar
                .floatingGlass()
                .padding(8)
                .frame(minWidth: 206, idealWidth: 236, maxWidth: 296, maxHeight: .infinity)

            CodeEditorView(text: $source, errorLines: errorLinesDict) { newText in
                if liveCompileEnabled {
                    engine.scheduleCompile(source: newText, engine: currentEngine, workingDirectory: workingDirectory, mainFileName: mainFileName)
                }
            }
            .background(Theme.base)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 1)
            .padding(8)
            .frame(minWidth: 376, maxHeight: .infinity)

            previewColumn
                .floatingGlass()
                .padding(8)
                .frame(minWidth: 376, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xEDEDF0))
        .onAppear(perform: loadInitial)
        .onChange(of: library.projects.first { $0.id == record.id }?.engine) { _, newValue in
            guard let newValue, newValue != currentEngine else { return }
            currentEngine = newValue
            engine.scheduleCompile(source: source, engine: newValue, workingDirectory: workingDirectory, mainFileName: mainFileName)
        }
        .onReceive(NotificationCenter.default.publisher(for: .blancRequestExportPDF)) { _ in exportPDF() }
        .onReceive(NotificationCenter.default.publisher(for: .blancRequestExportTeX)) { _ in exportTeX() }
    }

    // MARK: File tree sidebar

    private var fileTreeSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("content")
                .font(.custom("Syne-Regular", size: 20))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)
            Hairline().padding(.horizontal, 16).padding(.bottom, 10)

            DisclosureGroup(isExpanded: $folderExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries(in: projectDirectory), id: \.self) { url in
                        treeRow(url, depth: 0)
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(hex: 0x0088FF))
                    Text("Main Folder")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture { folderExpanded.toggle() }
                .hoverHighlight()
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(dropTarget == "root" ? Theme.accent : .clear, lineWidth: 1.5))
                .dropDestination(for: String.self) { items, _ in
                    handleDrop(items, into: projectDirectory)
                } isTargeted: { dropTarget = $0 ? "root" : (dropTarget == "root" ? nil : dropTarget) }
            }
            .padding(.horizontal, 14)
            .tint(Theme.textTertiary)

            Spacer()

            HStack(spacing: 14) {
                Button {
                    importFile()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(6)
                        .hoverHighlight(radius: 8)
                }
                .buttonStyle(.plain)
                .help("Upload file")

                Menu {
                    Button { createEntry(isFolder: true) } label: { Label("Folder", systemImage: "folder") }
                    Button { createEntry(isFolder: false) } label: { Label(".tex File", systemImage: "doc.text") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(6)
                .hoverHighlight(radius: 8)
                .help("New")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .alert("Rename Document", isPresented: $isRenaming) {
            TextField("Name", text: $renamingText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { commitRename() }
        }
    }

    // MARK: File tree helpers

    private func same(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// .tex files and folders inside `dir`; the project's main file always comes first.
    private func entries(in dir: URL) -> [URL] {
        _ = treeRefresh
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { !$0.lastPathComponent.hasPrefix("_blanc_build") && (isDirectory($0) || $0.pathExtension == "tex") }
            .sorted { x, y in
                if same(x, record.url) { return true }
                if same(y, record.url) { return false }
                return x.lastPathComponent.localizedStandardCompare(y.lastPathComponent) == .orderedAscending
            }
    }

    private func expandedBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { expandedFolders.contains(key) },
                set: { if $0 { expandedFolders.insert(key) } else { expandedFolders.remove(key) } })
    }

    private func treeRow(_ url: URL, depth: Int) -> AnyView {
        let isMain = same(url, record.url)
        if isDirectory(url) {
            let key = url.standardizedFileURL.path
            return AnyView(
                DisclosureGroup(isExpanded: expandedBinding(key)) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entries(in: url), id: \.self) { child in
                            treeRow(child, depth: depth + 1)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(hex: 0x0088FF))
                        Text(url.lastPathComponent)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .onTapGesture { expandedBinding(key).wrappedValue.toggle() }
                    .hoverHighlight()
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(dropTarget == key ? Theme.accent : .clear, lineWidth: 1.5))
                    .contextMenu { itemMenu(url) }
                    .draggable(url.path)
                    .dropDestination(for: String.self) { items, _ in
                        handleDrop(items, into: url)
                    } isTargeted: { dropTarget = $0 ? key : (dropTarget == key ? nil : dropTarget) }
                }
                .tint(Theme.textTertiary)
            )
        }
        let row = treeLabel(icon: "doc.text.fill", color: Theme.accent, title: url.lastPathComponent,
                            selected: same(url, activeFile), depth: depth) { selectFile(url) }
        if isMain {
            return AnyView(row.contextMenu { rowContextMenu })
        }
        return AnyView(row.contextMenu { itemMenu(url) }.draggable(url.path))
    }

    private func treeLabel(icon: String, color: Color, title: String, selected: Bool, depth: Int, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11.5))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .padding(.leading, 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.selection : .clear))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Theme.selectionStroke : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .hoverHighlight()
        .onTapGesture(perform: action)
    }

    @ViewBuilder
    private var rowContextMenu: some View {
        Button {
            renameTarget = record.url
            renamingText = record.name
            isRenaming = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Menu {
            Text("Main Folder")
        } label: {
            Label("Move to", systemImage: "folder")
        }
        Button {
            try? library.duplicate(record)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            exportTeX()
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        Divider()
        Button(role: .destructive) {
            library.delete(record)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Same menu as the main file, but operating on the file/folder on disk.
    @ViewBuilder
    private func itemMenu(_ url: URL) -> some View {
        Button {
            renameTarget = url
            renamingText = isDirectory(url) ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            isRenaming = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Menu {
            ForEach(moveDestinations(for: url), id: \.self) { dest in
                Button(same(dest, projectDirectory) ? "Main Folder" : dest.lastPathComponent) {
                    moveItem(url, into: dest)
                }
            }
        } label: {
            Label("Move to", systemImage: "folder")
        }
        Button {
            duplicateItem(url)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            downloadItem(url)
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        Divider()
        Button(role: .destructive) {
            deleteItem(url)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: File operations on the tree

    private func resolved(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    private func allFolders(in dir: URL) -> [URL] {
        entries(in: dir).filter { isDirectory($0) }.flatMap { [$0] + allFolders(in: $0) }
    }

    private func moveDestinations(for url: URL) -> [URL] {
        let src = resolved(url)
        return ([projectDirectory] + allFolders(in: projectDirectory)).filter { dest in
            let d = resolved(dest)
            return d != src && !d.hasPrefix(src + "/") && !same(dest, url.deletingLastPathComponent())
        }
    }

    private func remapActive(from old: URL, to new: URL) {
        let a = resolved(activeFile), o = resolved(old)
        if a == o { activeFile = new }
        else if a.hasPrefix(o + "/") { activeFile = new.appendingPathComponent(String(a.dropFirst(o.count + 1))) }
    }

    private func handleDrop(_ items: [String], into folder: URL) -> Bool {
        var moved = false
        for path in items where moveItem(URL(fileURLWithPath: path), into: folder) { moved = true }
        return moved
    }

    @discardableResult
    private func moveItem(_ src: URL, into folder: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path), !same(src, record.url), !same(src.deletingLastPathComponent(), folder) else { return false }
        let s = resolved(src), f = resolved(folder)
        guard f != s, !f.hasPrefix(s + "/") else { return false }
        let dest = folder.appendingPathComponent(src.lastPathComponent)
        guard !fm.fileExists(atPath: dest.path) else { return false }
        if same(src, activeFile) { try? source.write(to: activeFile, atomically: true, encoding: .utf8) }
        let activeBefore = activeFile
        do { try fm.moveItem(at: src, to: dest) } catch { return false }
        activeFile = activeBefore
        remapActive(from: src, to: dest)
        if !same(folder, projectDirectory) { expandedFolders.insert(folder.standardizedFileURL.path) }
        treeRefresh += 1
        return true
    }

    private func commitRename() {
        let name = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let target = renameTarget else { return }
        if same(target, record.url) { library.rename(record, to: name); return }
        let newName = isDirectory(target) || name.hasSuffix(".tex") ? name : name + ".tex"
        let dest = target.deletingLastPathComponent().appendingPathComponent(newName)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: dest.path) else { return }
        if same(target, activeFile) { try? source.write(to: activeFile, atomically: true, encoding: .utf8) }
        let activeBefore = activeFile
        guard (try? fm.moveItem(at: target, to: dest)) != nil else { return }
        activeFile = activeBefore
        remapActive(from: target, to: dest)
        treeRefresh += 1
    }

    private func duplicateItem(_ url: URL) {
        let fm = FileManager.default
        if same(url, activeFile) { try? source.write(to: activeFile, atomically: true, encoding: .utf8) }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var n = 1
        var dest: URL
        repeat {
            let nm = base + (n == 1 ? " copy" : " copy \(n)")
            dest = dir.appendingPathComponent(ext.isEmpty ? nm : nm + "." + ext)
            n += 1
        } while fm.fileExists(atPath: dest.path)
        try? fm.copyItem(at: url, to: dest)
        treeRefresh += 1
    }

    private func downloadItem(_ url: URL) {
        if same(url, activeFile) { try? source.write(to: activeFile, atomically: true, encoding: .utf8) }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
    }

    private func deleteItem(_ url: URL) {
        let fm = FileManager.default
        let affectsActive = resolved(activeFile) == resolved(url) || resolved(activeFile).hasPrefix(resolved(url) + "/")
        if (try? fm.trashItem(at: url, resultingItemURL: nil)) == nil { try? fm.removeItem(at: url) }
        if affectsActive {
            activeFile = record.url
            source = (try? String(contentsOf: record.url, encoding: .utf8)) ?? ""
            engine.scheduleCompile(source: source, engine: currentEngine, workingDirectory: workingDirectory, mainFileName: mainFileName)
        }
        treeRefresh += 1
    }

    private func selectFile(_ url: URL) {
        guard !same(url, activeFile) else { return }
        try? source.write(to: activeFile, atomically: true, encoding: .utf8)
        activeFile = url
        source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        engine.scheduleCompile(source: source, engine: currentEngine, workingDirectory: workingDirectory, mainFileName: mainFileName)
    }

    // MARK: Preview column (compile controls + PDF / failed state)

    private var previewColumn: some View {
        VStack(spacing: 0) {
            compileControls
            ZStack {
                switch engine.status {
                case .success(let pdfURL, _):
                    PDFPreviewView(url: pdfURL)
                case .failure:
                    compileFailedView
                case .compiling, .idle:
                    if !engine.isAnyEngineAvailable {
                        noEngineView
                    } else {
                        ProgressView("Preparing preview…")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var compileControls: some View {
        HStack(spacing: 10) {
            Button {
                engine.scheduleCompile(source: source, engine: currentEngine, workingDirectory: workingDirectory, mainFileName: mainFileName)
            } label: {
                Label("Compile", systemImage: "play.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(BlancPillButtonStyle())
            .fixedSize()
            .layoutPriority(2)

            diagnosticsBadges

            Spacer()

            Button {
                liveCompileEnabled.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(liveCompileEnabled ? Theme.accent : Theme.textTertiary)
                        .frame(width: 7, height: 7)
                    Text("Live Compile")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button("Export as PDF…") { exportPDF() }
                Button("Export as .tex…") { exportTeX() }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var diagnosticsBadges: some View {
        switch engine.status {
        case .compiling:
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("Compiling…").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        case .success where engine.warningCount == 0:
            Circle()
                .fill(Theme.success)
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
        default:
            HStack(spacing: 6) {
                if engine.errorCount > 0 {
                    Button { showingDiagnosticsPopover = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.octagon")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(engine.errorCount)")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.danger))
                    }
                    .buttonStyle(.plain)
                }
                if engine.warningCount > 0 {
                    Button { showingDiagnosticsPopover = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(engine.warningCount)")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.warning))
                    }
                    .buttonStyle(.plain)
                }
            }
            .popover(isPresented: $showingDiagnosticsPopover) {
                diagnosticsList
            }
        }
    }

    private var diagnosticsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(engine.diagnostics) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: entry.kind == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(entry.kind == .error ? Theme.danger : Theme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.line != nil ? "[\(entry.file), \(entry.line!)]" : "[\(entry.file)]")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                            Text(entry.message)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 320, height: min(CGFloat(engine.diagnostics.count) * 46 + 4, 320))
    }

    private var compileFailedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "xmark.octagon.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 72))
                .foregroundStyle(Theme.textTertiary)
            Text("Compile failed")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var noEngineView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(Theme.warning)
            Text("No TeX distribution found")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("Install MacTeX or TeX Live, then reopen this document.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Actions

    private func loadInitial() {
        source = (try? String(contentsOf: activeFile, encoding: .utf8)) ?? ""
        engine.scheduleCompile(source: source, engine: currentEngine, workingDirectory: workingDirectory, mainFileName: mainFileName)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                let dest = projectDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
            }
            treeRefresh += 1
        }
    }

    private func createEntry(isFolder: Bool) {
        let fm = FileManager.default
        var n = 0
        var url: URL
        repeat {
            let base = isFolder ? "folder" : "untitled"
            let name = n == 0 ? base : "\(base) \(n)"
            url = projectDirectory.appendingPathComponent(isFolder ? name : name + ".tex")
            n += 1
        } while fm.fileExists(atPath: url.path)
        if isFolder { try? fm.createDirectory(at: url, withIntermediateDirectories: true) }
        else { try? "".write(to: url, atomically: true, encoding: .utf8) }
        treeRefresh += 1
    }

    private func exportPDF() {
        guard case .success(let pdfURL, _) = engine.status else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = record.name
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: pdfURL, to: destination)
        }
    }

    private func exportTeX() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "tex") ?? .plainText]
        panel.nameFieldStringValue = record.name
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            try? source.write(to: destination, atomically: true, encoding: .utf8)
        }
    }
}
