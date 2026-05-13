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
    @State private var attachmentAlert: AttachmentAlert?
    @State private var showsContextPopover = false
    @State private var isTimelineNearBottom = true
    @State private var timelineDistanceFromBottom: CGFloat = 0
    @State private var autoFollowStreaming = true
    @State private var userIsDraggingTimeline = false
    @State private var followLayoutScrollScheduled = false
    @State private var initialBottomScrollThreadID: String?
    @State private var programmaticBottomScrollSettling = false
    @State private var programmaticBottomScrollGeneration = 0
    @AppStorage("mobidex.dismissedMacOSPrivacyWarning") private var dismissedMacOSPrivacyWarning = false
    @FocusState private var isComposerFocused: Bool
    private let conversationBottomID = "conversationBottom"
    private static let latestButtonShowDistance: CGFloat = 48
    private static let nearBottomRestoreDistance: CGFloat = 12
    private static let bottomScrollSettleDuration: TimeInterval = 0.3

    var body: some View {
        VStack(spacing: 0) {
            if let thread = model.selectedThread {
                macOSPrivacyWarningBanner(warning: macOSPrivacyWarning(for: thread.cwd))
                header(thread)
                Divider()
                detailPicker
                Divider()
                switch selectedDetail {
                case .chat:
                    timeline
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            composer
                        }
                case .changes:
                    SessionChangesView(cwd: thread.cwd)
                }
            } else if let project = model.selectedProject {
                macOSPrivacyWarningBanner(warning: project.macOSPrivacyWarning)
                projectHeader(project)
                Divider()
                ContentUnavailableView(
                    projectEmptyTitle,
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
                guard !items.isEmpty else { return }
                let threadID = model.selectedThreadID
                Task { await persistPhotoItems(items, selectedThreadID: threadID) }
            }
            .alert(item: $attachmentAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleImportedFiles(result)
            }
    }

    @ViewBuilder
    private func macOSPrivacyWarningBanner(warning: String?) -> some View {
        if let warning, !dismissedMacOSPrivacyWarning {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    dismissedMacOSPrivacyWarning = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss macOS privacy warning")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.12))
            Divider()
        }
    }

    private func macOSPrivacyWarning(for cwd: String) -> String? {
        ProjectRecord.macOSPrivacyWarning(for: [cwd])
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
            if !model.isAppServerConnected {
                Label("Connect to continue", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SessionStatusDot(status: thread.status)
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
            .buttonStyle(.borderedProminent)
            .disabled(!model.canCreateSession)
            .accessibilityIdentifier("projectNewSessionButton")
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
        let isStreaming = model.selectedThread?.status.isActive == true
        let liveSectionID = isStreaming ? model.conversationSections.last?.id : nil
        return ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.pendingApprovals) { approval in
                            ApprovalCard(approval: approval)
                                .environmentObject(model)
                        }
                        ForEach(model.conversationSections) { section in
                            ConversationSectionView(
                                section: section,
                                isLive: section.id == liveSectionID,
                                onLiveContentLayoutChanged: {
                                    requestFollowScrollAfterLayout(proxy, isStreaming: isStreaming)
                                }
                            )
                            .id(section.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(conversationBottomID)
                    }
                    .padding()
                }
                .coordinateSpace(name: "timelineScroll")
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded {
                    isComposerFocused = false
                })
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentSize.height - geometry.visibleRect.maxY)
                } action: { _, distance in
                    updateTimelineDistanceFromBottom(distance, isStreaming: isStreaming)
                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onScrollPhaseChange { _, newPhase in
                    switch newPhase {
                    case .tracking, .interacting:
                        programmaticBottomScrollSettling = false
                        userIsDraggingTimeline = true
                        if isStreaming {
                            autoFollowStreaming = false
                        }
                    case .decelerating:
                        userIsDraggingTimeline = true
                    default:
                        userIsDraggingTimeline = false
                        if isTimelineNearBottom {
                            autoFollowStreaming = true
                        }
                    }
                }
                if timelineDistanceFromBottom > Self.latestButtonShowDistance {
                    Button {
                        autoFollowStreaming = true
                        isTimelineNearBottom = true
                        timelineDistanceFromBottom = 0
                        scrollToConversationBottom(proxy)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.9)) {
                                scrollToConversationBottom(proxy)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scroll to latest message")
                    .padding(.trailing, 18)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
                .onAppear {
                    autoFollowStreaming = true
                    requestInitialBottomScrollIfNeeded(proxy)
                }
                .onChange(of: model.selectedThreadID) { _, _ in
                    autoFollowStreaming = true
                    isTimelineNearBottom = true
                    timelineDistanceFromBottom = 0
                    initialBottomScrollThreadID = nil
                    requestInitialBottomScrollIfNeeded(proxy)
                }
                .onChange(of: model.conversationRenderToken) { _, _ in
                    requestInitialBottomScrollIfNeeded(proxy)
                }
                .onChange(of: model.conversationFollowToken) { _, _ in
                    guard isStreaming, autoFollowStreaming, !userIsDraggingTimeline else { return }
                    scrollToConversationBottom(proxy)
                }
                .onChange(of: model.conversationSendToken) { _, _ in
                    autoFollowStreaming = true
                    isTimelineNearBottom = true
                    timelineDistanceFromBottom = 0
                    scrollToConversationBottom(proxy)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.9)) {
                            scrollToConversationBottom(proxy)
                        }
                    }
                }
                .onChange(of: model.selectedThread?.status) { oldStatus, status in
                    let wasStreaming = oldStatus?.isActive == true
                    let isStreaming = status?.isActive == true
                    if wasStreaming && !isStreaming && autoFollowStreaming {
                        scrollToConversationBottom(proxy)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToConversationBottom(proxy)
                        }
                    }
                }
        }
    }

    private var projectEmptyTitle: String {
        if model.isRefreshingSessions {
            return "Loading Sessions..."
        }
        return model.canSendMessage ? "No Sessions" : "Connect to Create a Session"
    }

    private func scrollToConversationBottom(_ proxy: ScrollViewProxy) {
        isTimelineNearBottom = true
        timelineDistanceFromBottom = 0
        programmaticBottomScrollGeneration &+= 1
        let generation = programmaticBottomScrollGeneration
        programmaticBottomScrollSettling = true
        proxy.scrollTo(conversationBottomID, anchor: .bottom)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bottomScrollSettleDuration) {
            guard programmaticBottomScrollGeneration == generation else { return }
            programmaticBottomScrollSettling = false
        }
    }

    private func requestInitialBottomScrollIfNeeded(_ proxy: ScrollViewProxy) {
        guard !model.conversationSections.isEmpty else { return }
        guard let selectedThreadID = model.selectedThreadID else { return }
        guard initialBottomScrollThreadID != selectedThreadID else { return }
        initialBottomScrollThreadID = selectedThreadID
        DispatchQueue.main.async {
            guard model.selectedThreadID == selectedThreadID else { return }
            scrollToConversationBottom(proxy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard model.selectedThreadID == selectedThreadID else { return }
                scrollToConversationBottom(proxy)
            }
        }
    }

    private func requestFollowScrollAfterLayout(_ proxy: ScrollViewProxy, isStreaming: Bool) {
        guard !followLayoutScrollScheduled else { return }
        followLayoutScrollScheduled = true
        DispatchQueue.main.async {
            followLayoutScrollScheduled = false
            guard isStreaming, autoFollowStreaming, !userIsDraggingTimeline else { return }
            scrollToConversationBottom(proxy)
        }
    }

    private func updateTimelineDistanceFromBottom(_ distance: CGFloat, isStreaming: Bool) {
        let clampedDistance = max(0, distance)
        if programmaticBottomScrollSettling {
            if clampedDistance <= Self.nearBottomRestoreDistance {
                programmaticBottomScrollSettling = false
            } else {
                return
            }
        }

        timelineDistanceFromBottom = clampedDistance
        let nextIsNearBottom = clampedDistance <= Self.nearBottomRestoreDistance
        if nextIsNearBottom != isTimelineNearBottom {
            isTimelineNearBottom = nextIsNearBottom
        }
        if nextIsNearBottom {
            autoFollowStreaming = true
        } else if isStreaming && userIsDraggingTimeline {
            autoFollowStreaming = false
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

                composerControlRow
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
        !hasComposerInput || !model.canSendMessage
    }

    private var sendButtonBackground: Color {
        sendVisuallyUnavailable ? Color.secondary.opacity(0.45) : Color.accentColor
    }

    private var hasComposerInput: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachmentPaths.isEmpty
    }

    private var sendVisuallyUnavailable: Bool {
        !hasComposerInput || model.connectionState != .connected
    }

    private var composerControlRow: some View {
        HStack(spacing: 8) {
            attachmentIcon

            accessLabel

            Spacer(minLength: 4)

            composerTrailingControls
        }
    }

    private var composerTrailingControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if shouldShowContextIndicator {
                    contextIndicator
                }
                modelLabel
                sendButton
            }
            HStack(spacing: 8) {
                modelLabel
                sendButton
            }
            sendButton
        }
    }

    private var attachmentIcon: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $selectedPhotoItems, matching: .images) {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Attach Photo")
            .accessibilityIdentifier("photoAttachmentButton")

            Button {
                isFileImporterPresented = true
            } label: {
                Image(systemName: "doc")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attach File")
            .accessibilityIdentifier("fileAttachmentButton")
        }
        .accessibilityLabel("Attach")
    }

    private var accessLabel: some View {
        Menu {
            ForEach(CodexAccessMode.allCases) { mode in
                Button {
                    model.selectedAccessMode = mode
                } label: {
                    Label {
                        Text(mode.label)
                    } icon: {
                        Image(systemName: mode == model.selectedAccessMode ? "checkmark" : mode.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: model.selectedAccessMode.systemImage)
                .font(.title3)
                .frame(width: 32, height: 32)
        }
        .font(.subheadline)
        .foregroundStyle(.orange)
        .accessibilityLabel("Next turn access mode \(model.selectedAccessMode.label)")
    }

    private var modelLabel: some View {
        Menu {
            ForEach(CodexReasoningEffortOption.allCases) { effort in
                Button {
                    model.selectedReasoningEffort = effort
                } label: {
                    Label {
                        Text(effort.label)
                    } icon: {
                        if effort == model.selectedReasoningEffort {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("5.5")
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44, minHeight: 32)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .accessibilityLabel("Model GPT-5.5 next turn reasoning \(model.selectedReasoningEffort.label)")
    }

    private var sendButton: some View {
        Button {
            submitComposerInput(queueWhenActive: false)
        } label: {
            Image(systemName: "arrow.up")
                .font(.title3.weight(.semibold))
                .frame(width: 42, height: 42)
                .foregroundStyle(.white)
                .background(sendButtonBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(sendDisabled)
        .contextMenu {
            if model.selectedThread?.status.isActive == true {
                Button("Send to Codex") {
                    submitComposerInput(queueWhenActive: false)
                }
                Button("Send as Follow-up") {
                    submitComposerInput(queueWhenActive: true)
                }
            }
        }
        .accessibilityLabel("Send")
        .accessibilityIdentifier("sendButton")
    }

    private func submitComposerInput(queueWhenActive: Bool) {
        let text = composerText
        let attachments = attachmentPaths
        isComposerFocused = false
        model.requestConversationSendScroll()
        Task {
            let sent = await model.sendComposerInput(
                text: text,
                localAttachmentPaths: attachments,
                queueWhenActive: queueWhenActive
            )
            guard sent else {
                attachmentAlert = AttachmentAlert(
                    title: "Message Not Sent",
                    message: model.statusMessage ?? "Mobidex could not send this message."
                )
                return
            }
            if composerText == text, attachmentPaths == attachments {
                composerText = ""
                attachmentPaths = []
                selectedPhotoItems = []
            }
        }
    }

    private var contextIndicator: some View {
        let fraction = model.contextUsageFraction
        let percent = model.contextUsagePercent
        return Button {
            showsContextPopover = true
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                    .frame(width: 20, height: 20)
                if let fraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 20, height: 20)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsContextPopover) {
            Text(percent.map { "Context window \($0)% used" } ?? "Context window unavailable")
                .font(.caption)
                .padding(10)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(percent.map { "Context window \($0) percent used" } ?? "Context window")
    }

    private var shouldShowContextIndicator: Bool {
        model.contextUsagePercent != nil
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

    @MainActor
    private func persistPhotoItems(_ items: [PhotosPickerItem], selectedThreadID: String?) async {
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
        guard model.selectedThreadID == selectedThreadID else {
            selectedPhotoItems = []
            return
        }
        if !savedPaths.isEmpty {
            attachmentPaths.append(contentsOf: savedPaths)
        } else {
            attachmentAlert = AttachmentAlert(
                title: "Photo Not Attached",
                message: "Mobidex could not read the selected photo."
            )
        }
        selectedPhotoItems = []
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            attachmentAlert = AttachmentAlert(
                title: "Files Not Attached",
                message: "Mobidex could not access the selected files."
            )
            return
        }
        var didAttachFile = false
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
                didAttachFile = true
            } catch {
                continue
            }
        }
        if !didAttachFile {
            attachmentAlert = AttachmentAlert(
                title: "Files Not Attached",
                message: "Mobidex could not copy the selected files into a readable upload location."
            )
        }
    }
}

private struct AttachmentAlert: Identifiable {
    var id = UUID()
    var title: String
    var message: String
}

private struct SessionStatusDot: View {
    let status: CodexThreadStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if shouldPulse {
                Circle()
                    .fill(color.opacity(isPulsing ? 0.10 : 0.28))
                    .frame(width: isPulsing ? 26 : 12, height: isPulsing ? 26 : 12)
            }
            Circle()
                .fill(color)
                .frame(width: 11, height: 11)
        }
        .frame(width: 28, height: 28)
        .animation(
            shouldPulse
                ? .easeInOut(duration: 1.05).repeatForever(autoreverses: true)
                : .default,
            value: isPulsing
        )
        .onAppear {
            isPulsing = shouldPulse
        }
        .onChange(of: shouldPulse) { _, shouldPulse in
            isPulsing = shouldPulse
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var shouldPulse: Bool {
        status.isActive && !reduceMotion
    }

    private var color: Color {
        switch status.indicator {
        case .needsAttention:
            return .red
        case .active, .inactive:
            return .green
        }
    }

    private var accessibilityLabel: String {
        switch status.indicator {
        case .needsAttention:
            return "Session needs attention"
        case .active:
            return "Session active"
        case .inactive:
            return "Session ready"
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
    var isLive = false
    var onLiveContentLayoutChanged: () -> Void = {}
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
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { oldHeight, newHeight in
            guard isLive, abs(newHeight - oldHeight) > 0.5 else { return }
            onLiveContentLayoutChanged()
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
            MarkdownText(section.body, id: section.id)
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
    private let id: String
    private let markdown: String

    init(_ markdown: String, id: String) {
        self.id = id
        self.markdown = ConversationTextPresentation.displayBody(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ConversationMarkdownRenderCache.shared.segments(for: id, markdown: markdown)) { segment in
                if let attributed = segment.attributed {
                    Text(attributed)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(segment.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct ConversationMarkdownSegment: Identifiable {
    var id: String
    var text: String
    var attributed: AttributedString?
}

@MainActor
private final class ConversationMarkdownRenderCache {
    static let shared = ConversationMarkdownRenderCache()

    private struct Entry {
        var markdown: String
        var prefix: String
        var prefixSegments: [ConversationMarkdownSegment]
        var segments: [ConversationMarkdownSegment]
    }

    private var entries: [String: Entry] = [:]
    private var accessOrder: [String] = []
    private let maximumEntries = 96
    private let targetTailCharacters = 4_096
    private let minimumReusablePrefixCharacters = 1_024

    func segments(for id: String, markdown: String) -> [ConversationMarkdownSegment] {
        if let entry = entries[id], entry.markdown == markdown {
            touch(id)
            return entry.segments
        }

        let previous = entries[id]
        let nextEntry = buildEntry(id: id, markdown: markdown, previous: previous)
        entries[id] = nextEntry
        touch(id)
        trimIfNeeded()
        return nextEntry.segments
    }

    private func buildEntry(id: String, markdown: String, previous: Entry?) -> Entry {
        guard markdown.count > minimumReusablePrefixCharacters,
              let anchor = reusableTailAnchor(in: markdown),
              anchor > markdown.startIndex
        else {
            let segments = parseSegments(id: id, namespace: "full", markdown: markdown)
            return Entry(markdown: markdown, prefix: "", prefixSegments: [], segments: segments)
        }

        let prefix = String(markdown[..<anchor])
        let tail = String(markdown[anchor...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixSegments: [ConversationMarkdownSegment]
        if let previous, previous.prefix == prefix {
            prefixSegments = previous.prefixSegments
        } else {
            prefixSegments = parseSegments(id: id, namespace: "prefix", markdown: prefix)
        }
        let tailSegments = parseSegments(id: id, namespace: "tail", markdown: tail)
        return Entry(markdown: markdown, prefix: prefix, prefixSegments: prefixSegments, segments: prefixSegments + tailSegments)
    }

    private func reusableTailAnchor(in markdown: String) -> String.Index? {
        guard markdown.count > targetTailCharacters + minimumReusablePrefixCharacters else {
            return nil
        }
        let tailStart = markdown.index(markdown.endIndex, offsetBy: -targetTailCharacters)
        var search = markdown[..<tailStart]
        while let range = search.range(of: "\n\n", options: .backwards) {
            let anchor = range.upperBound
            guard markdown.distance(from: markdown.startIndex, to: anchor) >= minimumReusablePrefixCharacters else {
                return nil
            }
            let prefix = markdown[..<anchor]
            let fenceCount = prefix.components(separatedBy: "```").count - 1
            let tildeFenceCount = prefix.components(separatedBy: "~~~").count - 1
            if fenceCount.isMultiple(of: 2), tildeFenceCount.isMultiple(of: 2) {
                return anchor
            }
            search = markdown[..<range.lowerBound]
        }
        return nil
    }

    private func parseSegments(id: String, namespace: String, markdown: String) -> [ConversationMarkdownSegment] {
        ConversationTextPresentation.markdownBlocks(from: markdown).enumerated().map { offset, block in
            let segmentID = "\(id)-\(namespace)-\(offset)-\(Self.stableHash(block))"
            return ConversationMarkdownSegment(
                id: segmentID,
                text: block,
                attributed: try? AttributedString(markdown: ConversationTextPresentation.markdownForRendering(from: block))
            )
        }
    }

    private func touch(_ id: String) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    private func trimIfNeeded() {
        guard accessOrder.count > maximumEntries else { return }
        for id in accessOrder.prefix(accessOrder.count - maximumEntries) {
            entries.removeValue(forKey: id)
        }
        accessOrder = Array(accessOrder.suffix(maximumEntries))
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
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

    static func markdownForRendering(from block: String) -> String {
        var renderedLines: [String] = []
        var isInFence = false
        let lines = block
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let text = String(line)
            let trimmedLine = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            let isFence = trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
            if isFence {
                renderedLines.append(text)
                isInFence.toggle()
            } else if isInFence || trimmedLine.isEmpty {
                renderedLines.append(text)
            } else {
                renderedLines.append(text + "  ")
            }
        }

        return renderedLines.joined(separator: "\n")
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
