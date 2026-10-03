//
//  Theme.swift
//  BLANC
//
//  Central design tokens, matched against the reference mockup:
//  soft white surfaces, a black pill "home" control, pastel circular
//  action icons, and a lavender selection tint in the file tree.
//

import SwiftUI

enum Theme {
    static let base = Color(hex: 0xFFFFFF)
    static let sidebar = Color(hex: 0xF7F7F8)
    static let surface = Color(hex: 0xFFFFFF)
    static let surfaceRaised = Color(hex: 0xF0F0F2)
    static let stroke = Color(hex: 0xE4E4E7)
    static let strokeSubtle = Color(hex: 0xEDEDEF)

    static let textPrimary = Color(hex: 0x1C1C1E)
    static let textSecondary = Color(hex: 0x6E6E76)
    static let textTertiary = Color(hex: 0xA0A0A8)

    static let accent = Color(hex: 0x5B5BF0)           // indigo-blue accent used for links/selection
    static let success = Color(hex: 0x00C8B3)
    static let warning = Color(hex: 0xFFCC00)
    static let danger = Color(hex: 0xFF383C)

    static let inkBlack = Color(hex: 0x10181E)          // black chrome (home pill, compile button)

    /// Lavender tint for the selected row in the file tree.
    static let selection = Color(hex: 0xEDEBFC)
    static let selectionStroke = Color(hex: 0xD9D4F7)

    /// Pastel circular icon backgrounds on the home screen.
    enum IconTile {
        static let importBG = Color(hex: 0xFBE7EC)
        static let importFG = Color(hex: 0xE0536F)
        static let newBG = Color(hex: 0xEDE7FB)
        static let newFG = Color(hex: 0x7A5CE0)
        static let packageBG = Color(hex: 0xE2F6F8)
        static let packageFG = Color(hex: 0x2AB6C4)
    }

    // MARK: Syntax colors — light background, Xcode-esque
    enum Syntax {
        static let command = Color(hex: 0x1C6FD1)
        static let bracket = Color(hex: 0x3B3B3F)
        static let optional = Color(hex: 0x6E6E76)
        static let comment = Color(hex: 0xE07B2A)       // matches the orange "% TRACE:" line in the mockup
        static let math = Color(hex: 0x1C8B5A)
        static let environment = Color(hex: 0x9B2D8E)
        static let text = Color(hex: 0x1D1D1F)
        static let special = Color(hex: 0xB5540A)
        static let errorBackground = Color(hex: 0xFF383C, alpha: 0.5)
        static let errorStripe = Color(hex: 0xFF383C)
    }

    static let cornerRadius: CGFloat = 14
    static let cornerRadiusSmall: CGFloat = 8
    static let pillRadius: CGFloat = 100

    static let editorFont = "SF Mono"
}

/// Subtle highlight on pointer hover so every control gives feedback.
struct HoverHighlight: ViewModifier {
    var radius: CGFloat = 6
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black.opacity(hovering ? 0.07 : 0)))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    func hoverHighlight(radius: CGFloat = 6) -> some View { modifier(HoverHighlight(radius: radius)) }
}

/// 0.5pt separator used everywhere so line weights stay consistent.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.stroke).frame(height: 0.5)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// A flat, minimal button style matching the app's aesthetic.
struct BlancButtonStyle: ButtonStyle {
    var prominent: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .fill(prominent ? Theme.inkBlack.opacity(configuration.isPressed ? 0.85 : 1) : Theme.surfaceRaised.opacity(configuration.isPressed ? 0.6 : 1))
            )
            .foregroundStyle(prominent ? .white : Theme.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .stroke(prominent ? .clear : Theme.stroke, lineWidth: 1)
            )
    }
}

/// The black, pill-shaped "Compile" button seen above the preview pane.
struct BlancPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.inkBlack.opacity(configuration.isPressed ? 0.85 : 1)))
            .foregroundStyle(.white)
    }
}

struct BlancCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.strokeSubtle, lineWidth: 1)
            )
    }
}

extension View {
    /// Liquid Glass on macOS 26+, falls back to a material on older systems.
    /// (`#if os` is compile-time only and can't check versions, so `#available` is used.)
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self
                .background(shape.fill(.regularMaterial))
                .background(shape.fill((tint ?? .clear).opacity(tint == nil ? 0 : 0.85)))
                .overlay(shape.stroke(Color.black.opacity(0.06), lineWidth: 0.5))
        }
    }

    /// Floating Liquid Glass pane with continuous rounded corners.
    func floatingGlass(radius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .clipShape(shape)
            .adaptiveGlass(in: shape)
    }

    func blancCard() -> some View { modifier(BlancCard()) }
}

/// GlassEffectContainer on macOS 26+, plain passthrough before.
struct AdaptiveGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}
