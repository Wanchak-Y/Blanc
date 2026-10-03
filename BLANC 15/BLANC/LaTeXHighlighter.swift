//
//  LaTeXHighlighter.swift
//  BLANC
//
//  Cheap, fast, regex-based highlighting so real-time edits never stutter.
//

import AppKit
import Foundation
import SwiftUI

enum LaTeXHighlighter {
    private struct Rule {
        let regex: NSRegularExpression
        let color: NSColor
    }

    private static let rules: [Rule] = {
        func rule(_ pattern: String, _ color: NSColor, options: NSRegularExpression.Options = []) -> Rule {
            Rule(regex: try! NSRegularExpression(pattern: pattern, options: options), color: color)
        }
        return [
            // Comments first so they win visually where they overlap other patterns.
            rule(#"%.*$"#, NSColor(Theme.Syntax.comment), options: [.anchorsMatchLines]),
            // \begin{env} / \end{env} — highlight the environment name distinctly.
            rule(#"\\(begin|end)\{[^}]*\}"#, NSColor(Theme.Syntax.environment)),
            // Generic commands like \section, \textbf, \frac
            rule(#"\\[a-zA-Z]+\*?"#, NSColor(Theme.Syntax.command)),
            // Math delimiters and their contents ($...$, \[...\])
            rule(#"\$[^$]*\$"#, NSColor(Theme.Syntax.math)),
            // Curly / square brackets
            rule(#"[\{\}]"#, NSColor(Theme.Syntax.bracket)),
            rule(#"\[[^\]\n]*\]"#, NSColor(Theme.Syntax.optional)),
            // Special characters
            rule(#"[&#~^_]"#, NSColor(Theme.Syntax.special)),
        ]
    }()

    /// Applies syntax colors to `storage` for the given full text range.
    static func highlight(_ storage: NSTextStorage) {
        let text = storage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        guard fullRange.length > 0 else { return }

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor(Theme.Syntax.text), range: fullRange)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 7
        storage.addAttribute(.paragraphStyle, value: para, range: fullRange)

        for rule in rules {
            rule.regex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.foregroundColor, value: rule.color, range: match.range)
            }
        }
        storage.endEditing()
    }
}
