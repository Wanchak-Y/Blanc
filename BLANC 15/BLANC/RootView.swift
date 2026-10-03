//
//  RootView.swift
//  BLANC
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: DocumentLibrary
    @State private var openRecords: [ProjectRecord] = []
    @State private var activeId: UUID?
    @State private var searchText: String = ""

    private var activeRecord: ProjectRecord? {
        openRecords.first { $0.id == activeId }
    }

    var body: some View {
        VStack(spacing: 0) {
            TopChromeBar(
                tabs: openRecords.map { OpenTab(id: $0.id, title: $0.name) },
                activeTabId: activeId,
                engine: library.projects.first { $0.id == activeId }?.engine,
                onHome: { activeId = nil },
                onSelectTab: { activeId = $0 },
                onCloseTab: closeTab,
                onMoveTab: moveTab,
                onSelectEngine: { eng in
                    if let rec = activeRecord { library.updateEngine(rec, engine: eng) }
                },
                searchText: $searchText
            )

            Group {
                if let activeRecord {
                    EditorView(record: activeRecord)
                        .id(activeRecord.id)
                } else {
                    HomeView(searchText: $searchText, openTab: openTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.base)
        .ignoresSafeArea(.container, edges: .top)
    }

    private func openTab(_ record: ProjectRecord) {
        if !openRecords.contains(where: { $0.id == record.id }) {
            openRecords.append(record)
        }
        activeId = record.id
    }

    private func moveTab(_ dragged: String, before target: UUID) {
        guard let from = openRecords.firstIndex(where: { $0.id.uuidString == dragged }),
              let to = openRecords.firstIndex(where: { $0.id == target }), from != to else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            openRecords.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    private func closeTab(_ id: UUID) {
        openRecords.removeAll { $0.id == id }
        if activeId == id {
            activeId = openRecords.last?.id
        }
    }
}
