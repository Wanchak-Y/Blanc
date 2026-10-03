//
//  BLANCApp.swift
//  BLANC
//
//  A minimal, elegant LaTeX editor for macOS.
//

import SwiftUI
import CoreText

@main
struct BLANCApp: App {
    @StateObject private var library = DocumentLibrary()

    init() {
        if let url = Bundle.main.url(forResource: "Syne-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(.light)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document…") {
                    NotificationCenter.default.post(name: .blancRequestNewDocument, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .saveItem) {
                Button("Export as PDF…") {
                    NotificationCenter.default.post(name: .blancRequestExportPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Export as .tex…") {
                    NotificationCenter.default.post(name: .blancRequestExportTeX, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let blancRequestNewDocument = Notification.Name("blancRequestNewDocument")
    static let blancRequestExportPDF = Notification.Name("blancRequestExportPDF")
    static let blancRequestExportTeX = Notification.Name("blancRequestExportTeX")
}
