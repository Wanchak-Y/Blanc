//
//  NewDocumentSheet.swift
//  BLANC
//

import SwiftUI

struct NewDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: DocumentLibrary

    @State private var name: String = ""
    @State private var preset: DocumentLanguagePreset = .english

    var onCreated: (ProjectRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Document")
                    .font(.system(size: 18, weight: .semibold))
                Text("Choose a name and a starting environment.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("FILE NAME")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(0.6)
                TextField("Untitled", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).fill(Theme.surfaceRaised))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).stroke(Theme.stroke, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("PRIMARY LANGUAGE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(0.6)

                HStack(spacing: 10) {
                    ForEach(DocumentLanguagePreset.allCases) { option in
                        PresetCard(option: option, isSelected: preset == option) {
                            preset = option
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(BlancButtonStyle())
                Button("Create") {
                    guard let record = try? library.createProject(name: name, preset: preset) else { return }
                    onCreated(record)
                    dismiss()
                }
                .buttonStyle(BlancButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.base)
    }
}

private struct PresetCard: View {
    let option: DocumentLanguagePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                Text(option.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(option.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).fill(Theme.surfaceRaised))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .stroke(isSelected ? Theme.accent : Theme.stroke, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
