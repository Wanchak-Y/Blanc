//
//  DocumentLibrary.swift
//  BLANC
//
//  Manages the on-disk project library: recent files, creation, presets.
//

import Foundation
import SwiftUI
import Combine

enum DocumentLanguagePreset: String, Codable, CaseIterable, Identifiable {
    case english
    case cjk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: return "English"
        case .cjk: return "CJK (中日韓)"
        }
    }

    var subtitle: String {
        switch self {
        case .english: return "Standard Latin typesetting with pdfLaTeX"
        case .cjk: return "Preconfigured CJK environment with XeLaTeX + ctex"
        }
    }

    var systemImage: String {
        switch self {
        case .english: return "textformat.abc"
        case .cjk: return "character.zh"
        }
    }

    /// Recommended engine for this preset. The user can still change it later.
    var recommendedEngine: TeXEngine {
        switch self {
        case .english: return .pdflatex
        case .cjk: return .xelatex
        }
    }

    var template: String {
        switch self {
        case .english:
            return """
            \\documentclass[11pt]{article}
            \\usepackage[margin=1in]{geometry}
            \\usepackage{amsmath}
            \\usepackage{amssymb}

            \\title{Untitled Document}
            \\author{}
            \\date{\\today}

            \\begin{document}
            \\maketitle

            \\section{Introduction}
            Start writing here.

            \\end{document}
            """
        case .cjk:
            return """
            \\documentclass[11pt]{ctexart}
            \\usepackage[margin=1in]{geometry}
            \\usepackage{amsmath}
            \\usepackage{amssymb}

            \\title{无标题文档}
            \\author{}
            \\date{\\today}

            \\begin{document}
            \\maketitle

            \\section{引言}
            在此开始写作。

            \\end{document}
            """
        }
    }
}

enum TeXEngine: String, Codable, CaseIterable, Identifiable {
    case pdflatex
    case xelatex

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pdflatex: return "pdfLaTeX"
        case .xelatex: return "XeLaTeX"
        }
    }
    /// Binary name to look up on PATH / common TeX Live locations.
    var binaryName: String {
        switch self {
        case .pdflatex: return "pdflatex"
        case .xelatex: return "xelatex"
        }
    }
}

struct ProjectRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: URL
    var preset: DocumentLanguagePreset
    var engine: TeXEngine
    var lastOpened: Date
    var createdAt: Date

    var displaySubtitle: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: lastOpened)
    }
}

@MainActor
final class DocumentLibrary: ObservableObject {
    @Published private(set) var projects: [ProjectRecord] = []

    private let indexURL: URL
    private let rootDirectory: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = support.appendingPathComponent("BLANC", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.rootDirectory = root
        self.indexURL = root.appendingPathComponent("index.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ProjectRecord].self, from: data) else {
            projects = []
            return
        }
        // Drop entries whose backing file has disappeared.
        projects = decoded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    @discardableResult
    func createProject(name: String, preset: DocumentLanguagePreset) throws -> ProjectRecord {
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : name
        let projectDir = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let fileURL = projectDir.appendingPathComponent("\(safeName).tex")
        try preset.template.write(to: fileURL, atomically: true, encoding: .utf8)

        let record = ProjectRecord(
            id: UUID(),
            name: safeName,
            url: fileURL,
            preset: preset,
            engine: preset.recommendedEngine,
            lastOpened: Date(),
            createdAt: Date()
        )
        projects.insert(record, at: 0)
        persist()
        return record
    }

    func touch(_ record: ProjectRecord) {
        guard let idx = projects.firstIndex(where: { $0.id == record.id }) else { return }
        projects[idx].lastOpened = Date()
        persist()
    }

    func updateEngine(_ record: ProjectRecord, engine: TeXEngine) {
        guard let idx = projects.firstIndex(where: { $0.id == record.id }) else { return }
        projects[idx].engine = engine
        persist()
    }

    func rename(_ record: ProjectRecord, to newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == record.id }) else { return }
        projects[idx].name = newName
        persist()
    }

    func delete(_ record: ProjectRecord) {
        projects.removeAll { $0.id == record.id }
        try? FileManager.default.removeItem(at: record.url.deletingLastPathComponent())
        persist()
    }

    @discardableResult
    func duplicate(_ record: ProjectRecord) throws -> ProjectRecord {
        let content = (try? String(contentsOf: record.url, encoding: .utf8)) ?? ""
        let projectDir = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let newName = record.name + " copy"
        let fileURL = projectDir.appendingPathComponent(record.url.lastPathComponent)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let newRecord = ProjectRecord(
            id: UUID(),
            name: newName,
            url: fileURL,
            preset: record.preset,
            engine: record.engine,
            lastOpened: Date(),
            createdAt: Date()
        )
        projects.insert(newRecord, at: 0)
        persist()
        return newRecord
    }

    func importExistingFile(at sourceURL: URL) throws -> ProjectRecord {
        let projectDir = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let destURL = projectDir.appendingPathComponent(sourceURL.lastPathComponent)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let record = ProjectRecord(
            id: UUID(),
            name: sourceURL.deletingPathExtension().lastPathComponent,
            url: destURL,
            preset: .english,
            engine: .pdflatex,
            lastOpened: Date(),
            createdAt: Date()
        )
        projects.insert(record, at: 0)
        persist()
        return record
    }
}
