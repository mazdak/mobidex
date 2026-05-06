import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ConversationView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var composerText = ""
    @State private var selectedDetail: SessionDetailMode = .chat
    @State private var attachmentPaths: [String] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isFileImporterPresented = false
    @State private var userWantsTimelineFollow = true
    @FocusState private var isComposerFocused: Bool
    private let conversationBottomID = "conversationBottom"

    var body: some View {
        VStack(spacing: 0) {
            if let thread = model.selectedThread {
                header(thread)
                Divider()
                detailPicker
                Divider()
                switch selectedDetail {
                case .chat:
                    timeline
                    composer
                case .changes:
                    SessionChangesView(cwd: thread.cwd)
                }
            } else if let project = model.selectedProject {
                projectHeader(project)
                Divider()
                ContentUnavailableView(
                    model.canSendMessage ? "No Sessions" : "Connect to Create a Session",
                    systemImage: "bubble.left.and.bubble.right"
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a Session", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model.selectedThread?.title ?? model.selectedProject?.displayName ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
            .onChange(of: model.selectedThreadID) { _, _ in
                selectedDetail = .chat
                attachmentPaths = []
            }
            .onChange(of: selectedPhotoItems) { _, items in
                Task { await persistPhotoItems(items) }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleImportedFiles(result)
            }
    }

    private func header(_ thread: CodexThread) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(thread.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(thread.cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.canInterruptActiveTurn {
                Button {
                    Task { await model.interruptActiveTurn() }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Stop Turn")
                .accessibilityIdentifier("stopTurnButton")
            }
            if thread.status.isActive {
                Label(model.selectedActivityLabel ?? thread.status.sessionLabel, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if !model.canSendMessage {
                Label("Connect to continue", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func projectHeader(_ project: ProjectRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await model.startNewSession() }
            } label: {
                Label("New Session", systemImage: "plus.bubble")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canCreateSession)
            .accessibilityHint(model.canSendMessage ? "Creates a Codex session for this project." : "Connect to the server before creating a session.")
            .accessibilityIdentifier("newSessionButton")
        }
        .padding()
    }

    private var detailPicker: some View {
        Picker("Session Detail", selection: $selectedDetail) {
            ForEach(SessionDetailMode.allCases) { mode in
                Label(mode.label, systemImage: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .accessibilityIdentifier("sessionDetailPicker")
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(model.pendingApprovals) { approval in
                                ApprovalCard(approval: approval)
                                    .environmentObject(model)
                            }
                            ForEach(model.conversationSections) { section in
                                ConversationSectionView(section: section)
                                    .id(section.id)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(conversationBottomID)
                                .background {
                                    GeometryReader { bottomGeometry in
                                        Color.clear.preference(
                                            key: TimelineBottomPreferenceKey.self,
                                            value: bottomGeometry.frame(in: .named("timelineScroll")).maxY
                                        )
                                    }
                                }
                        }
                    }
                    .coordinateSpace(name: "timelineScroll")
                    .padding()
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(TapGesture().onEnded {
                        isComposerFocused = false
                    })
                    .simultaneousGesture(DragGesture().onChanged { _ in
                        userWantsTimelineFollow = false
                    })
                    .onPreferenceChange(TimelineBottomPreferenceKey.self) { bottomY in
                        if bottomY <= geometry.size.height + 44 {
                            userWantsTimelineFollow = true
                        }
                    }
                    if model.isSelectedThreadLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading session")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 10)
                        .accessibilityIdentifier("sessionLoadingIndicator")
                    }
                }
                .onAppear {
                    userWantsTimelineFollow = true
                    scrollToConversationBottom(proxy)
                }
                .onChange(of: model.selectedThreadID) { _, _ in
                    userWantsTimelineFollow = true
                    scrollToConversationBottom(proxy)
                }
                .onChange(of: model.conversationRevision) { _, _ in
                    if userWantsTimelineFollow {
                        scrollToConversationBottom(proxy)
                    }
                }
                .onChange(of: model.isSelectedThreadLoading) { _, loading in
                    if !loading, userWantsTimelineFollow {
                        scrollToConversationBottom(proxy)
                    }
                }
            }
        }
    }

    private func scrollToConversationBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(conversationBottomID, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                TextField("Ask for follow-up changes", text: $composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...6)
                    .font(.body)
                    .focused($isComposerFocused)
                    .accessibilityIdentifier("messageComposer")

                if !attachmentPaths.isEmpty {
                    attachmentStrip
                }

                ViewThatFits(in: .horizontal) {
                    composerControlRow(showModelReasoning: true, showAccessText: true)
                    composerControlRow(showModelReasoning: false, showAccessText: true)
                    compactComposerControlRow
                    minimalComposerControlRow
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var sendDisabled: Bool {
        (composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachmentPaths.isEmpty)
            || !model.canSendMessage
    }

    private var sendButtonBackground: Color {
        sendDisabled ? Color.secondary.opacity(0.45) : Color.accentColor
    }

    private func composerControlRow(showModelReasoning: Bool, showAccessText: Bool) -> some View {
        HStack(spacing: showAccessText ? 14 : 12) {
            attachmentIcon

            accessLabel(showText: showAccessText)

            Spacer(minLength: 8)

            contextIndicator

            modelLabel(showReasoning: showModelReasoning)

            sendButton
        }
    }

    private var compactComposerControlRow: some View {
        HStack(spacing: 12) {
            attachmentIcon

            accessLabel(showText: false)

            Spacer(minLength: 6)

            contextIndicator
            modelLabel(showReasoning: false)

            sendButton
        }
    }

    private var minimalComposerControlRow: some View {
        HStack(spacing: 12) {
            attachmentIcon

            Spacer(minLength: 0)

            sendButton
        }
    }

    private var attachmentIcon: some View {
        Menu {
            PhotosPicker(selection: $selectedPhotoItems, matching: .images) {
                Label("Photos", systemImage: "photo")
            }
            Button {
                isFileImporterPresented = true
            } label: {
                Label("Files", systemImage: "doc")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .accessibilityLabel("Attach")
    }

    private func accessLabel(showText: Bool) -> some View {
        Menu {
            ForEach(CodexAccessMode.allCases) { mode in
                Button {
                    model.selectedAccessMode = mode
                } label: {
                    Label("Next turn: \(mode.label)", systemImage: mode.systemImage)
                }
            }
        } label: {
            Label {
                if showText {
                    Text(model.selectedAccessMode.label)
                }
            } icon: {
                Image(systemName: model.selectedAccessMode.systemImage)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.orange)
        .disabled(model.selectedThread?.status.isActive == true)
        .accessibilityLabel("Next turn access mode \(model.selectedAccessMode.label)")
    }

    private func modelLabel(showReasoning: Bool) -> some View {
        Menu {
            ForEach(CodexReasoningEffortOption.allCases) { effort in
                Button {
                    model.selectedReasoningEffort = effort
                } label: {
                    Text("Next turn: \(effort.label)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("5.5")
                    .fontWeight(.medium)
                if showReasoning {
                    Text(model.selectedReasoningEffort.label)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .disabled(model.selectedThread?.status.isActive == true)
        .accessibilityLabel("Model GPT-5.5 next turn reasoning \(model.selectedReasoningEffort.label)")
    }

    private var sendButton: some View {
        Button {
            let text = composerText
            let attachments = attachmentPaths
            isComposerFocused = false
            Task {
                let sent = await model.sendComposerInput(
                    text: text,
                    localAttachmentPaths: attachments,
                    queueWhenActive: false
                )
                guard sent else { return }
                if composerText == text, attachmentPaths == attachments {
                    composerText = ""
                    attachmentPaths = []
                    selectedPhotoItems = []
                }
            }
        } label: {
            Image(systemName: "arrow.up")
                .font(.title3.weight(.semibold))
                .frame(width: 42, height: 42)
                .foregroundStyle(.white)
                .background(sendButtonBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(sendDisabled)
        .accessibilityLabel("Send")
        .accessibilityIdentifier("sendButton")
    }

    private var contextIndicator: some View {
        let fraction = model.contextUsageFraction
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                .frame(width: 18, height: 18)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
            }
        }
        .accessibilityLabel(fraction.map { "Context window \(Int($0 * 100)) percent used" } ?? "Context window")
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachmentPaths, id: \.self) { path in
                    HStack(spacing: 5) {
                        Image(systemName: "paperclip")
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .lineLimit(1)
                        Button {
                            attachmentPaths.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
                }
            }
        }
    }

    private func persistPhotoItems(_ items: [PhotosPickerItem]) async {
        var savedPaths: [String] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                continue
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mobidex-photo-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            do {
                try data.write(to: url, options: .atomic)
                savedPaths.append(url.path)
            } catch {
                continue
            }
        }
        if !savedPaths.isEmpty {
            attachmentPaths.append(contentsOf: savedPaths)
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            return
        }
        for url in urls {
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mobidex-file-\(UUID().uuidString)", isDirectory: true)
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: destination)
                attachmentPaths.append(destination.path)
            } catch {
                continue
            }
        }
    }
}

private enum SessionDetailMode: String, CaseIterable, Identifiable {
    case chat
    case changes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat: "Chat"
        case .changes: "Changes"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .changes: "doc.text.magnifyingglass"
        }
    }
}

private struct TimelineBottomPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ApprovalCard: View {
    @EnvironmentObject private var model: AppViewModel
    let approval: PendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(approval.title, systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
            if !approval.detail.isEmpty {
                Text(approval.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    Task { await model.respond(to: approval, accept: true) }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("approveButton")

                Button(role: .destructive) {
                    Task { await model.respond(to: approval, accept: false) }
                } label: {
                    Label("Decline", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("declineButton")
            }
        }
        .padding()
        .background(.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.yellow.opacity(0.35))
        }
    }
}

struct ConversationSectionView: View {
    let section: ConversationSection
    @State private var isExpanded = false

    var body: some View {
        HStack {
            if section.kind == .user {
                Spacer(minLength: 36)
            }
            sectionCard
            .padding(10)
            .frame(maxWidth: 680, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            if section.kind != .user {
                Spacer(minLength: 36)
            }
        }
    }

    private var sectionCard: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            if section.isCollapsedByDefault {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    headerRow(showDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse \(section.title)" : "Expand \(section.title)")
            } else {
                headerRow(showDisclosure: false)
            }

            if !section.isCollapsedByDefault || isExpanded {
                expandedContent
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !section.body.isEmpty {
                bodyText
                    .font(bodyFont)
                    .textSelection(.enabled)
            }
            if let detail = section.detail, !detail.isEmpty {
                Text(detail)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func headerRow(showDisclosure: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(accent)
                .font(headerIconFont)
            Text(section.title)
                .font(headerFont)
                .foregroundStyle(.secondary)
                .lineLimit(section.isCollapsedByDefault ? 2 : 1)
            if let status = section.status, !status.isEmpty {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.14), in: Capsule())
            }
            if showDisclosure {
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
    }

    @ViewBuilder
    private var bodyText: some View {
        if section.rendersMarkdown {
            MarkdownText(section.body)
        } else {
            Text(section.body)
        }
    }

    private var sectionSpacing: CGFloat {
        section.isCollapsedByDefault && !isExpanded ? 0 : 7
    }

    private var headerIconFont: Font {
        section.usesCompactTypography ? .caption : .body
    }

    private var headerFont: Font {
        section.usesCompactTypography ? .caption2.weight(.semibold) : .caption.weight(.semibold)
    }

    private var bodyFont: Font {
        switch section.kind {
        case .command, .fileChange:
            .system(.caption, design: .monospaced)
        case .tool, .agent:
            .caption
        case .assistant, .reasoning, .plan, .review, .system:
            .callout
        default:
            .body
        }
    }

    private var detailFont: Font {
        section.usesCompactTypography ? .caption2 : .caption
    }

    private var iconName: String {
        switch section.kind {
        case .user: "person.fill"
        case .assistant: "sparkles"
        case .reasoning: "brain.head.profile"
        case .plan: "checklist"
        case .command: "terminal"
        case .fileChange: "doc.badge.gearshape"
        case .tool: "wrench.and.screwdriver"
        case .agent: "person.2"
        case .search: "magnifyingglass"
        case .media: "photo"
        case .review: "text.badge.checkmark"
        case .system: "info.circle"
        }
    }

    private var accent: Color {
        switch section.kind {
        case .user: .blue
        case .assistant: .green
        case .reasoning: .purple
        case .command: .orange
        case .fileChange: .pink
        case .tool, .agent: .teal
        case .plan, .review: .indigo
        case .search, .media, .system: .secondary
        }
    }

    private var background: Color {
        switch section.kind {
        case .user:
            .blue.opacity(0.12)
        case .assistant:
            .green.opacity(0.10)
        default:
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}

private struct MarkdownText: View {
    private let markdown: String

    init(_ markdown: String) {
        self.markdown = ConversationTextPresentation.displayBody(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ConversationTextPresentation.markdownBlocks(from: markdown).enumerated()), id: \.offset) { _, block in
                if let attributed = try? AttributedString(markdown: block) {
                    Text(attributed)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(block)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

enum ConversationTextPresentation {
    static func displayBody(from body: String) -> String {
        stripCodexAppDirectives(from: body)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func markdownBlocks(from body: String) -> [String] {
        let normalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var blocks: [String] = []
        var currentLines: [Substring] = []
        var isInFence = false

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmedLine = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~") {
                isInFence.toggle()
            }
            if trimmedLine.isEmpty && !isInFence {
                if !currentLines.isEmpty {
                    blocks.append(currentLines.joined(separator: "\n"))
                    currentLines = []
                }
            } else {
                currentLines.append(line)
            }
        }
        if !currentLines.isEmpty {
            blocks.append(currentLines.joined(separator: "\n"))
        }

        return blocks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stripCodexAppDirectives(from body: String) -> String {
        var visibleLines: [Substring] = []
        var isInFence = false

        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmedLine = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~") {
                isInFence.toggle()
                visibleLines.append(line)
            } else if isInFence || !isCodexAppDirectiveLine(trimmedLine) {
                visibleLines.append(line)
            }
        }

        return visibleLines.joined(separator: "\n")
    }

    private static func isCodexAppDirectiveLine(_ line: String) -> Bool {
        var remainder = line[...]
        var foundDirective = false

        while !remainder.isEmpty {
            remainder = remainder.drop(while: { $0 == " " || $0 == "\t" })
            if remainder.isEmpty {
                return foundDirective
            }
            guard let name = knownCodexDirectiveName(atStartOf: remainder) else {
                return false
            }
            remainder = remainder.dropFirst(2 + name.count)
            guard remainder.first == "{" else {
                return false
            }
            guard let closeBrace = remainder.firstIndex(of: "}") else {
                return false
            }
            remainder = remainder[remainder.index(after: closeBrace)...]
            foundDirective = true
        }

        return foundDirective
    }

    private static func knownCodexDirectiveName(atStartOf text: Substring) -> String? {
        let names = [
            "archive",
            "code-comment",
            "git-commit",
            "git-create-branch",
            "git-create-pr",
            "git-push",
            "git-stage",
        ]
        return names.first { text.hasPrefix("::\($0)") }
    }
}
