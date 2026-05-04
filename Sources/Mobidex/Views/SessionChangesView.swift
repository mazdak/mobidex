import SwiftUI
import gitdiff

struct SessionChangesView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedPath: String?

    let cwd: String

    var body: some View {
        VStack(spacing: 0) {
            changesHeader
            Divider()
            if model.diffSnapshot.isEmpty {
                ContentUnavailableView(
                    model.isAppServerConnected ? "No Changes" : "Connect to Check Changes",
                    systemImage: "doc.text.magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    fileList
                        .frame(width: 280)
                    Divider()
                    diffPane
                }
            } else {
                VStack(spacing: 0) {
                    fileList
                        .frame(maxHeight: 190)
                    Divider()
                    diffPane
                }
            }
        }
        .task(id: cwd) {
            await model.refreshDiffSnapshot(cwd: cwd)
        }
        .onChange(of: model.diffSnapshot.files) { _, files in
            guard let selectedPath, files.contains(where: { $0.path == selectedPath }) else {
                self.selectedPath = files.first?.path
                return
            }
        }
    }

    private var changesHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Changed Files")
                    .font(.headline)
                Text(cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.isRefreshingChanges {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await model.refreshDiffSnapshot(cwd: cwd) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!model.isAppServerConnected || model.isRefreshingChanges)
            .accessibilityIdentifier("refreshChangesButton")
        }
        .padding()
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.diffSnapshot.files) { file in
                    Button {
                        selectedPath = file.path
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(file.path == selectedDiffFile?.path ? .blue : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.path)
                                    .font(.subheadline.weight(file.path == selectedDiffFile?.path ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text("\(changedLineCount(file.diff)) changed \(changedLineCount(file.diff) == 1 ? "line" : "lines")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(file.path == selectedDiffFile?.path ? Color.accentColor.opacity(0.10) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    Divider()
                        .padding(.leading, 42)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var diffPane: some View {
        ScrollView {
            DiffRenderer(diffText: selectedDiffFile?.diff ?? model.diffSnapshot.diff)
                .diffTheme(colorScheme == .dark ? .dark : .light)
                .diffLineNumbers(true)
                .diffWordWrap(true)
                .padding()
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("diffPane")
    }

    private var selectedDiffFile: ChangedFileDiff? {
        if let selectedPath, let file = model.diffSnapshot.files.first(where: { $0.path == selectedPath }) {
            return file
        }
        return model.diffSnapshot.files.first
    }

    private func changedLineCount(_ diff: String) -> Int {
        diff.split(separator: "\n").filter { line in
            (line.hasPrefix("+") && !line.hasPrefix("+++"))
                || (line.hasPrefix("-") && !line.hasPrefix("---"))
        }.count
    }
}
