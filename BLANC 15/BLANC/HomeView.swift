//
//  HomeView.swift
//  BLANC
//

import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var library: DocumentLibrary
    @Binding var searchText: String
    var openTab: (ProjectRecord) -> Void

    @State private var showingNewSheet = false
    @State private var showingPackageComposerHint = false

    private var filtered: [ProjectRecord] {
        guard !searchText.isEmpty else { return library.projects }
        return library.projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    header
                    actionTiles
                }
                .padding(.top, 28)

                Hairline()
                    .padding(.top, 34)

                filesSection
                    .padding(.top, 24)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .background(Theme.base)
        .sheet(isPresented: $showingNewSheet) {
            NewDocumentSheet { record in
                openTab(record)
            }
            .environmentObject(library)
        }
        .onReceive(NotificationCenter.default.publisher(for: .blancRequestNewDocument)) { _ in
            showingNewSheet = true
        }
    }

    private var header: some View {
        Image("blancw_logo")
            .resizable()
            .scaledToFit()
            .frame(height: 64)
    }

    private var actionTiles: some View {
        HStack(spacing: 28) {
            Spacer(minLength: 0)
            ActionTile(
                title: "Input Existing File...",
                systemImage: "tray.and.arrow.down.fill",
                iconColor: Theme.IconTile.importFG,
                background: Theme.IconTile.importBG,
                action: importExistingFile
            )
            ActionTile(
                title: "Create New File...",
                systemImage: "long.text.page.and.pencil.fill",
                iconColor: Theme.IconTile.newFG,
                background: Theme.IconTile.newBG,
                action: { showingNewSheet = true }
            )
            ActionTile(
                title: "Package Composer",
                systemImage: "plus.rectangle.on.folder.fill",
                iconColor: Theme.IconTile.packageFG,
                background: Theme.IconTile.packageBG,
                action: { showingPackageComposerHint = true }
            )
        }
        .popover(isPresented: $showingPackageComposerHint) {
            Text("Package Composer is coming soon.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(12)
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("files")
                .font(.custom("Syne-Regular", size: 17))
                .foregroundStyle(Theme.textPrimary)

            if filtered.isEmpty {
                Text(library.projects.isEmpty ? "No documents yet — create your first one above." : "No documents match your search.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, record in
                        FileRow(record: record) {
                            library.touch(record)
                            openTab(record)
                        } onDelete: {
                            library.delete(record)
                        }
                        Hairline()
                    }
                }
                .overlay(Hairline(), alignment: .top)
            }
        }
    }

    private func importExistingFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "tex") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let record = try? library.importExistingFile(at: url) {
                openTab(record)
            }
        }
    }
}

private struct ActionTile: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    let background: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 68, height: 68)
                    .adaptiveGlass(in: Circle(), tint: background)
                    .scaleEffect(hovering ? 1.04 : 1)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }
}

private struct FileRow: View {
    let record: ProjectRecord
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.preset.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, alignment: .leading)

            Text(record.name)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            // Always laid out (no jitter); visible while the pointer is anywhere on the row.
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)

            Text(record.displayDateOnly)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
    }
}

private extension ProjectRecord {
    var displayDateOnly: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd"
        return df.string(from: lastOpened)
    }
}
