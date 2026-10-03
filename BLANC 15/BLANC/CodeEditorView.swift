//
//  CodeEditorView.swift
//  BLANC
//
//  A lightweight NSViewRepresentable text editor with LaTeX syntax coloring,
//  a line-number gutter, and inline highlighting of lines that produced a
//  compile error — matching the reference mockup.
//

import AppKit
import SwiftUI

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    /// 1-indexed line numbers that should be tinted red, with their message.
    var errorLines: [Int: String] = [:]
    var onChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ErrorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor(Theme.base)
        textView.insertionPointColor = NSColor(Theme.accent)
        textView.textContainerInset = NSSize(width: 12, height: 14)
        textView.string = text
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(Theme.base)
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasHorizontalRuler = false
        scrollView.rulersVisible = true

        LaTeXHighlighter.highlight(textView.textStorage!)
        textView.errorLines = errorLines
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ErrorTextView else { return }
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            LaTeXHighlighter.highlight(textView.textStorage!)
            textView.selectedRanges = selected
        }
        if textView.errorLines != errorLines { textView.errorLines = errorLines }
        context.coordinator.lastErrorLines = errorLines
        (nsView.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeEditorView
        private var highlightWorkItem: DispatchWorkItem?
        var lastErrorLines: [Int: String] = [:]

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            parent.text = newText
            parent.onChange(newText)

            if let scrollView = textView.enclosingScrollView {
                (scrollView.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
            }

            // Re-highlight on a short delay so fast typing stays smooth.
            highlightWorkItem?.cancel()
            let work = DispatchWorkItem { [weak textView] in
                guard let storage = textView?.textStorage else { return }
                LaTeXHighlighter.highlight(storage)
            }
            highlightWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }
}

/// A minimal line-number gutter, styled to match the mockup's editor.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(contentDidChange), name: NSText.didChangeNotification, object: textView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func contentDidChange() { needsDisplay = true }

    private func drawHairline() {
        NSColor(Theme.stroke).setFill()
        let rect = NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height)
        rect.fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(Theme.surface).setFill()
        bounds.fill()

        guard let textView = textView as? ErrorTextView else { return }
        let visibleY = textView.visibleRect.origin.y
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(Theme.textTertiary)
        ]
        for row in textView.visibleLines() {
            let y = row.rect.minY - visibleY
            let isError = textView.errorLines[row.number] != nil
            if isError {
                NSColor(Theme.Syntax.errorBackground).setFill()
                NSRect(x: 0, y: y, width: bounds.width, height: row.rect.height).fill()
                NSColor(Theme.Syntax.errorStripe).setFill()
                NSRect(x: 0, y: y, width: 2, height: row.rect.height).fill()
            } else if textView.hoverLine == row.number {
                NSColor(white: 0, alpha: 0.05).setFill()
                NSRect(x: 0, y: y, width: bounds.width, height: row.rect.height).fill()
            }
            let numberString = "\(row.number)" as NSString
            let size = numberString.size(withAttributes: attrs)
            numberString.draw(
                at: NSPoint(x: ruleThickness - size.width - 10, y: y + (row.rect.height - 7 - size.height) / 2),
                withAttributes: attrs
            )
        }
        drawHairline()
    }
}

/// NSTextView that paints full-width error rows (with the reason on the
/// right) and a light-grey hover row, instead of tinting glyph backgrounds.
final class ErrorTextView: NSTextView {
    var errorLines: [Int: String] = [:] { didSet { redrawRows() } }
    var hoverLine: Int? { didSet { if oldValue != hoverLine { redrawRows() } } }
    private var tracking: NSTrackingArea?

    private func redrawRows() {
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        hoverLine = visibleLines().first { $0.rect.minY <= point.y && point.y < $0.rect.maxY }?.number
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverLine = nil
    }

    struct Row { let number: Int; let rect: NSRect; let codeEndX: CGFloat }

    /// Rows (full line fragments, incl. line spacing) intersecting the visible area.
    func visibleLines() -> [Row] {
        guard let lm = layoutManager, let tc = textContainer else { return [] }
        let ns = string as NSString
        guard ns.length > 0 else { return [] }
        let glyphs = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var number = ns.substring(to: chars.location).components(separatedBy: "\n").count
        var index = chars.location
        var rows: [Row] = []
        while index < NSMaxRange(chars) {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let gr = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var rect = NSRect.null
            var g = gr.location
            while g < NSMaxRange(gr) {
                var eff = NSRange()
                rect = rect.union(lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &eff))
                g = max(NSMaxRange(eff), g + 1)
            }
            let firstUsed = lm.lineFragmentUsedRect(forGlyphAt: gr.location, effectiveRange: nil)
            rect.origin.y += textContainerOrigin.y
            rows.append(Row(number: number, rect: NSRect(x: 0, y: rect.minY, width: bounds.width, height: rect.height),
                            codeEndX: firstUsed.maxX + textContainerOrigin.x))
            number += 1
            index = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
        return rows
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let red = NSColor(Theme.Syntax.errorStripe)
        for row in visibleLines() {
            if let message = errorLines[row.number] {
                NSColor(Theme.Syntax.errorBackground).setFill()
                row.rect.fill()
                drawMessage(message, in: row, color: red)
            } else if hoverLine == row.number {
                NSColor(white: 0, alpha: 0.05).setFill()
                row.rect.fill()
            }
        }
    }

    private func drawMessage(_ message: String, in row: Row, color: NSColor) {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let iconSize: CGFloat = 14, gap: CGFloat = 6, margin: CGFloat = 14
        let available = bounds.width - margin - (row.codeEndX + 20)
        guard available > iconSize + gap + 30 else { return }
        let textSize = (message as NSString).size(withAttributes: attrs)
        let textWidth = min(ceil(textSize.width), available - iconSize - gap)
        let originX = bounds.width - margin - textWidth - gap - iconSize
        let midY = row.rect.minY + (row.rect.height - 7) / 2
        if let symbol = NSImage(systemSymbolName: "xmark.octagon.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))) {
            symbol.draw(in: NSRect(x: originX, y: midY - iconSize / 2, width: iconSize, height: iconSize),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        (message as NSString).draw(
            in: NSRect(x: originX + iconSize + gap, y: midY - textSize.height / 2, width: textWidth, height: textSize.height),
            withAttributes: attrs
        )
    }
}
