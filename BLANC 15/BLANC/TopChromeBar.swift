//
//  TopChromeBar.swift
//  BLANC
//
//  The bar under the native traffic lights: a black "home" pill, a row of
//  pill-shaped tabs for open documents, and a search field — mirrors the
//  reference mockup exactly.
//

import AppKit
import SwiftUI

struct OpenTab: Identifiable, Equatable {
    let id: UUID
    var title: String
}

struct TopChromeBar: View {
    let tabs: [OpenTab]
    let activeTabId: UUID?
    var engine: TeXEngine? = nil
    var onHome: () -> Void
    var onSelectTab: (UUID) -> Void
    var onCloseTab: (UUID) -> Void
    var onMoveTab: (String, UUID) -> Void = { _, _ in }
    var onSelectEngine: (TeXEngine) -> Void = { _ in }
    @Binding var searchText: String

    static let height: CGFloat = 52

    var body: some View {
        HStack(spacing: 20) {
            // Leading space reserved for the native traffic lights (same row).
            Color.clear.frame(width: 58, height: 1)

            Button(action: onHome) {
                Image(systemName: "house")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 32)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.inkBlack))
            }
            .buttonStyle(.plain)
            .modifier(HomeHover())

            // Stretched gray track holding the Liquid Glass tabs.
            AdaptiveGlassContainer(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(tabs) { tab in
                            TabPill(
                                id: tab.id,
                                title: tab.title,
                                isActive: tab.id == activeTabId,
                                onSelect: { onSelectTab(tab.id) },
                                onClose: { onCloseTab(tab.id) },
                                onDropDragged: { onMoveTab($0, tab.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Capsule().fill(Color(hex: 0xE5E5E8)))

            if let engine {
                Picker("", selection: Binding(get: { engine }, set: onSelectEngine)) {
                    ForEach(TeXEngine.allCases) { eng in
                        Text(eng.title).tag(eng)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 12)
            .frame(width: 200, height: 32)
            .background(Capsule().fill(Color.white))
            .overlay(Capsule().stroke(Theme.strokeSubtle, lineWidth: 0.5))
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .background(WindowChromeConfigurator())
    }
}

private struct HomeHover: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.05 : 1)
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }
}

private struct TabPill: View {
    let id: UUID
    let title: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDropDragged: (String) -> Void

    private let gray = Color(hex: 0x8E8E93)

    var body: some View {
        HStack(spacing: 6) {
            // Fixed-width tab: short titles leave blank space, long ones end in "…".
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(isActive ? Color.white : Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isActive ? Color.white : Theme.textSecondary)
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.28) : Color.black.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(width: 124, height: 26)
        .adaptiveGlass(in: Capsule(), tint: isActive ? gray : nil)
        .overlay(Capsule().stroke(Color.white.opacity(isActive ? 0.25 : 0.9), lineWidth: 0.75))
        .contentShape(Capsule())
        .onTapGesture(perform: onSelect)
        .help(title)
        .draggable(id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            onDropDragged(first)
            return true
        }
    }
}

/// Makes the title bar transparent and vertically centers the native traffic
/// lights in the 52pt chrome bar, so they sit on the same row as Home / tabs.
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            Self.layoutButtons(in: window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Self.layoutButtons(in: window) }

            let names: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification,
                NSWindow.didEnterFullScreenNotification,
            ]
            for name in names {
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                    Self.layoutButtons(in: window)
                    DispatchQueue.main.async { Self.layoutButtons(in: window) }
                }
            }
            if let closeBtn = window.standardWindowButton(.closeButton) {
                closeBtn.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: closeBtn, queue: .main) { _ in
                    Self.layoutButtons(in: window)
                }
            }
            if let container = window.standardWindowButton(.closeButton)?.superview?.superview {
                container.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: container, queue: .main) { _ in
                    Self.layoutButtons(in: window)
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// close.superview = title-bar view, its superview = title-bar container,
    /// whose superview is the window's frame view. Every write is guarded so
    /// the frame-change observer above can never loop.
    private static func layoutButtons(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview,
              let container = titlebar.superview,
              let host = container.superview else { return }
        let h = TopChromeBar.height
        let y: CGFloat = host.isFlipped ? 0 : host.bounds.height - h
        let target = NSRect(x: 0, y: y, width: host.bounds.width, height: h)
        if container.frame != target { container.frame = target }
        if titlebar.frame != container.bounds { titlebar.frame = container.bounds }
        // Left inset = top inset; every button is shifted by the same delta (idempotent).
        let inset = (h - close.frame.height) / 2
        let dx = inset - close.frame.origin.x
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let b = window.standardWindowButton(type) else { continue }
            if abs(dx) > 0.5 { b.setFrameOrigin(NSPoint(x: b.frame.origin.x + dx, y: b.frame.origin.y)) }
            let ny = (h - b.frame.height) / 2
            if abs(b.frame.origin.y - ny) > 0.5 {
                b.setFrameOrigin(NSPoint(x: b.frame.origin.x, y: ny))
            }
        }
    }
}
