import AppKit
import SwiftUI

@MainActor
struct HistoryView: View {
    let dictation: DictationModel
    @State private var copiedID: HistoryEntry.ID?

    var body: some View {
        Group {
            if dictation.history.isEmpty && dictation.historyWarnings.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Diktate", systemImage: "waveform")
                } description: {
                    Text("Richte Mikrofon, Ordner und Mistral-Key in den Einstellungen ein. Dann in ein Textfeld klicken und \(dictation.shortcut.displayName) drücken. Jedes Diktat landet hier, auch wenn das Einfügen nicht klappt.")
                }
            } else {
                List {
                    if !dictation.historyWarnings.isEmpty {
                        Section {
                            ForEach(Array(dictation.historyWarnings.enumerated()), id: \.offset) { _, warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .font(.callout)
                            }
                        }
                    }
                    ForEach(days, id: \.day) { group in
                        Section(Self.title(for: group.day)) {
                            ForEach(group.entries) { entry in
                                HistoryRow(entry: entry, copied: copiedID == entry.id, canRetry: dictation.canStart,
                                           copy: { copy(entry) }, retry: { dictation.retry(entry.id) })
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
            }
        }
        .frame(minWidth: 560, minHeight: 350)
    }

    private var days: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        return Dictionary(grouping: dictation.history) { calendar.startOfDay(for: $0.createdAt) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Heute" }
        if calendar.isDateInYesterday(day) { return "Gestern" }
        return calendar.isDate(day, equalTo: .now, toGranularity: .year)
            ? day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    private func copy(_ entry: HistoryEntry) {
        guard let text = entry.transcript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedID == entry.id { copiedID = nil }
        }
    }
}

/// Transcript first; metadata stays quiet; status only speaks up when something needs action.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let copied: Bool
    let canRetry: Bool
    let copy: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let text = entry.transcript {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                status
            }
            if let message = entry.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                metadata
                Spacer(minLength: 12)
                action
                Button("Im Finder zeigen", systemImage: "folder", action: revealInFinder)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Aufnahme im Finder zeigen")
            }
        }
        .padding(.vertical, 6)
        // Otherwise SwiftUI starts the separator at whichever Label it finds first in the row.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .contextMenu {
            if entry.transcript != nil {
                Button("Kopieren", systemImage: "doc.on.doc", action: copy)
            } else if entry.status != .transcribing {
                Button("Erneut transkribieren", systemImage: "arrow.clockwise", action: retry).disabled(!canRetry)
            }
            Button("Im Finder zeigen", systemImage: "folder", action: revealInFinder)
        }
    }

    private func revealInFinder() {
        guard let folder = try? FolderStore.resolve(entry.folderBookmark).url else { return }
        let file = folder.appendingPathComponent(entry.filename)
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }

    @ViewBuilder private var status: some View {
        switch entry.status {
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Wird transkribiert …").foregroundStyle(.secondary)
            }
        case .failed:
            statusLabel("Transkription fehlgeschlagen", symbol: "xmark.octagon.fill", tint: .red)
        case .interrupted:
            statusLabel("Aufnahme unterbrochen", symbol: "exclamationmark.circle.fill", tint: .orange)
        case .preparing, .recording:
            statusLabel("Aufnahme läuft", symbol: "record.circle", tint: .red)
        case .pending where entry.sourceLabel != nil:
            statusLabel("Browser-Aufnahme gespeichert", symbol: "waveform", tint: .secondary)
        case .pending, .complete:
            statusLabel("Noch nicht transkribiert", symbol: "clock", tint: .orange)
        }
    }

    private func statusLabel(_ title: String, symbol: String, tint: some ShapeStyle) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            Text(entry.createdAt, format: .dateTime.hour().minute())
            if let duration = entry.duration {
                Text("·")
                Text(Self.format(duration))
            }
            if let source = entry.sourceLabel {
                Text("·")
                Label(source, systemImage: "globe").labelStyle(.titleAndIcon)
            }
            if entry.transcript != nil {
                switch entry.insertion {
                case .confirmed:
                    Text("·")
                    Label("Eingefügt", systemImage: "checkmark").labelStyle(.titleAndIcon)
                case .unavailable, .unconfirmed:
                    Text("·")
                    Text("Nicht eingefügt").help(entry.insertion.title)
                case .notAttempted, .historyOnly:
                    EmptyView()
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .help(entry.filename)
    }

    @ViewBuilder private var action: some View {
        if entry.transcript != nil {
            Button(action: copy) {
                Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
        } else if entry.status != .transcribing {
            Button(entry.sourceLabel != nil && entry.status == .pending ? "Transkribieren" : "Erneut transkribieren",
                   systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(.borderless)
                .disabled(!canRetry)
        }
    }

    private static func format(_ duration: TimeInterval) -> String {
        duration < 60
            ? duration.formatted(.number.precision(.fractionLength(1))) + " s"
            : Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)) + " min"
    }
}
