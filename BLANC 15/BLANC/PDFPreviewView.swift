//
//  PDFPreviewView.swift
//  BLANC
//

import PDFKit
import SwiftUI

struct PDFPreviewView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        guard let url else {
            nsView.document = nil
            return
        }
        // Preserve scroll position across reloads triggered by recompiles.
        let priorPage = nsView.currentPage
        if let doc = PDFDocument(url: url) {
            nsView.document = doc
            if let priorPage, let idx = nsView.document?.index(for: priorPage), idx < doc.pageCount {
                nsView.go(to: doc.page(at: idx) ?? doc.page(at: 0)!)
            }
        }
    }
}
