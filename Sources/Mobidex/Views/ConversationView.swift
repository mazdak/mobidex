import Foundation
import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ConversationView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var composerText = ""
    @State private var composerEditGeneration = 0
    @State private var photoAttachmentGeneration = 0
    @State private var composerDrafts: [String: ComposerDraft] = [:]
    @State private var selectedDetail: SessionDetailMode = .chat
    @State private var attachmentPaths: [String] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var audioRecorder: AudioComposerRecorder?
    @State private var isRecordingAudio = false
    @State private var didDisableIdleTimerForRecording = false
    @State private var idleTimerWasDisabledBeforeRecording = false
    @State private var isTranscribingAudio = false
    @State private var attachmentAlert: AttachmentAlert?
    @State private var isQueueSheetPresented = false
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
                if model.isStartingNewSession {
                    newSessionStartingView
                } else {
                    ContentUnavailableView("Select a Session", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("Select a Session", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedDetail != .chat, isRecordingAudio, model.selectedThread != nil {
                audioRecordingDock
            }
        }
        .navigationTitle(model.selectedThread?.title ?? model.selectedProject?.displayName ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if horizontalSizeClass == .compact, model.selectedThread != nil, model.selectedProject != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    conversationNewSessionButton
                }
            }
        }
            .onAppear {
                loadComposerDraft(for: composerDraftKey)
            }
            .onChange(of: composerDraftKey) { oldKey, newKey in
                selectedDetail = .chat
                saveComposerDraft(for: oldKey)
                loadComposerDraft(for: newKey)
                selectedPhotoItems = []
                photoAttachmentGeneration &+= 1
                composerEditGeneration &+= 1
            }
            .onChange(of: model.selectedThreadID) { _, newThreadID in
                focusComposerForFreshThreadIfNeeded(threadID: newThreadID)
            }
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                composerEditGeneration &+= 1
                photoAttachmentGeneration &+= 1
                let draftKey = composerDraftKey
                let attachmentGeneration = photoAttachmentGeneration
                Task {
                    await persistPhotoItems(
                        items,
                        composerDraftKey: draftKey,
                        attachmentGeneration: attachmentGeneration
                    )
                }
            }
            .alert(item: $attachmentAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $selectedPhotoItems,
                matching: .images
            )
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleImportedFiles(result)
            }
            .onChange(of: isRecordingAudio) { _, isRecording in
                updateRecordingIdleTimer(isRecording: isRecording)
            }
            .onDisappear {
                updateRecordingIdleTimer(isRecording: false)
            }
    }

    private var conversationNewSessionButton: some View {
        Menu {
            Button {
                Task { await model.startNewSession(location: .codexWorktree) }
            } label: {
                Label("Start in New Worktree", systemImage: "arrow.triangle.branch")
            }
            Button {
                Task { await model.startNewSession(location: .projectDirectory) }
            } label: {
                Label("Start in Project Directory", systemImage: "folder")
            }
        } label: {
            if model.isStartingNewSession {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "plus.bubble")
            }
        }
        .disabled(!model.canChooseNewSessionLocation || model.isStartingNewSession)
        .accessibilityLabel(model.isStartingNewSession ? "Starting New Session" : "New Session")
        .accessibilityIdentifier("projectNewSessionButton")
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
                    .id(model.selectedThreadID ?? "no-selected-thread")
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
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(8)
                    .accessibilityLabel("Scroll to latest message")
                    .padding(.trailing, 10)
                    .padding(.bottom, 4)
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
        if model.isStartingNewSession {
            return "Starting New Session..."
        }
        return "No Session Selected"
    }

    private var projectEmptyDescription: String {
        if model.isStartingNewSession {
            return model.statusMessage ?? "Mobidex is preparing a fresh Codex thread."
        }
        if let statusMessage = model.statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        return model.canSendMessage ? "Start the first prompt for this project." : "Connect to load sessions for this project."
    }

    private var projectEmptyView: some View {
        ContentUnavailableView(
            projectEmptyTitle,
            systemImage: "bubble.left.and.bubble.right",
            description: Text(projectEmptyDescription)
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.canSendMessage {
                    composer
                }
            }
    }

    private var sessionRefreshView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newSessionStartingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(projectEmptyTitle)
                .font(.headline)
            Text(projectEmptyDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                if !model.queuedTurnInputs.isEmpty {
                    queuedMessagesTray
                }

                TextField("Ask for follow-up changes", text: composerTextBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...6)
                    .font(.body)
                    .focused($isComposerFocused)
                    .disabled(isTranscribingAudio)
                    .accessibilityIdentifier("messageComposer")

                if !attachmentPaths.isEmpty {
                    attachmentStrip
                }

                if isRecordingAudio {
                    audioRecordingIndicator
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
        .sheet(isPresented: $isQueueSheetPresented) {
            QueuedMessagesSheet()
                .environmentObject(model)
                .presentationDetents([.medium, .large])
        }
    }

    private func focusComposerForFreshThreadIfNeeded(threadID: String?) {
        guard let threadID, model.selectedThread?.id == threadID, model.selectedThread?.turns.isEmpty == true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard model.selectedThread?.id == threadID, model.selectedThread?.turns.isEmpty == true else { return }
            isComposerFocused = true
        }
    }

    private var queuedMessagesTray: some View {
        Button {
            isQueueSheetPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .foregroundStyle(.secondary)
                Text(queueTrayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var queueTrayTitle: String {
        let count = model.queuedTurnInputs.count
        guard count == 1, let item = model.queuedTurnInputs.first else {
            return "\(count) queued"
        }
        return "1 queued: \(item.preview)"
    }

    private var sendDisabled: Bool {
        isTranscribingAudio || !hasComposerInput || !model.canSendMessage
    }

    private var sendButtonBackground: Color {
        sendVisuallyUnavailable ? Color.secondary.opacity(0.45) : Color.accentColor
    }

    private var hasComposerInput: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachmentPaths.isEmpty
    }

    private var composerTextBinding: Binding<String> {
        Binding {
            composerText
        } set: { newValue in
            composerText = newValue
            composerEditGeneration &+= 1
            saveComposerDraft(for: composerDraftKey)
        }
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
                modelLabel
                sendButton
            }
            sendButton
        }
    }

    private var audioRecordingIndicator: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text("Recording")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            RecordingActivityBars()

            Spacer(minLength: 8)

            Button {
                stopAndTranscribeAudio()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityLabel("Stop Recording")
            .accessibilityIdentifier("stopRecordingButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var audioRecordingDock: some View {
        audioRecordingIndicator
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
    }

    private var attachmentIcon: some View {
        Menu {
            Button {
                toggleAudioRecording()
            } label: {
                Label(isRecordingAudio ? "Stop Recording" : "Record Audio", systemImage: isRecordingAudio ? "stop.circle" : "mic")
            }
            .disabled(isTranscribingAudio)

            Button {
                isPhotoPickerPresented = true
            } label: {
                Label("Photo", systemImage: "photo")
            }
            .accessibilityLabel("Attach Photo")
            .accessibilityIdentifier("photoAttachmentButton")

            Button {
                isFileImporterPresented = true
            } label: {
                Label("File", systemImage: "doc")
            }
            .accessibilityLabel("Attach File")
            .accessibilityIdentifier("fileAttachmentButton")
        } label: {
            Image(systemName: isTranscribingAudio ? "waveform" : "plus")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
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
                Text("5.5 \(model.selectedReasoningEffort.label)")
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 32)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .accessibilityLabel("Model GPT-5.5 next turn reasoning \(model.selectedReasoningEffort.label)")
    }

    @ViewBuilder
    private var sendButton: some View {
        if model.selectedThread?.status.isActive == true {
            sendButtonBase
                .contextMenu {
                    Button("Queue after Current Turn") {
                        submitComposerInput(queueWhenActive: true)
                    }
                    Button("Steer Active Turn") {
                        submitComposerInput(queueWhenActive: false)
                    }
                }
        } else {
            sendButtonBase
        }
    }

    private var sendButtonBase: some View {
        Button {
            submitComposerInput(queueWhenActive: model.selectedThread?.status.isActive == true)
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

    private func submitComposerInput(queueWhenActive: Bool) {
        let text = composerText
        let attachments = attachmentPaths
        let submittedDraftKey = composerDraftKey
        let submittedEditGeneration = composerEditGeneration
        isComposerFocused = false
        composerText = ""
        attachmentPaths = []
        clearComposerDraft(for: submittedDraftKey)
        photoAttachmentGeneration &+= 1
        selectedPhotoItems = []
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
                guard composerDraftKey == submittedDraftKey,
                      composerEditGeneration == submittedEditGeneration else {
                    return
                }
                composerText = text
                attachmentPaths = attachments
                saveComposerDraft(for: submittedDraftKey)
                return
            }
        }
    }

    private var composerDraftKey: String? {
        guard let serverID = model.selectedServerID else { return nil }
        if let threadID = model.selectedThreadID {
            return "server:\(serverID.uuidString)|thread:\(threadID)"
        }
        if let projectID = model.selectedProjectID {
            return "server:\(serverID.uuidString)|project:\(projectID.uuidString)"
        }
        return "server:\(serverID.uuidString)|new"
    }

    private func saveComposerDraft(for key: String?) {
        guard let key else { return }
        if composerText.isEmpty && attachmentPaths.isEmpty {
            composerDrafts.removeValue(forKey: key)
        } else {
            composerDrafts[key] = ComposerDraft(text: composerText, attachmentPaths: attachmentPaths)
        }
    }

    private func loadComposerDraft(for key: String?) {
        guard let key, let draft = composerDrafts[key] else {
            composerText = ""
            attachmentPaths = []
            return
        }
        composerText = draft.text
        attachmentPaths = draft.attachmentPaths
    }

    private func clearComposerDraft(for key: String?) {
        guard let key else { return }
        composerDrafts.removeValue(forKey: key)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(attachmentPaths, id: \.self) { path in
                    ComposerAttachmentTile(
                        path: path,
                        onRemove: {
                            attachmentPaths.removeAll { $0 == path }
                            composerEditGeneration &+= 1
                            saveComposerDraft(for: composerDraftKey)
                        }
                    )
                }
            }
        }
    }

    @MainActor
    private func persistPhotoItems(
        _ items: [PhotosPickerItem],
        composerDraftKey: String?,
        attachmentGeneration: Int
    ) async {
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
        guard self.composerDraftKey == composerDraftKey,
              photoAttachmentGeneration == attachmentGeneration else {
            selectedPhotoItems = []
            return
        }
        if !savedPaths.isEmpty {
            attachmentPaths.append(contentsOf: savedPaths)
            saveComposerDraft(for: composerDraftKey)
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
        if didAttachFile {
            composerEditGeneration &+= 1
            saveComposerDraft(for: composerDraftKey)
        }
        if !didAttachFile {
            attachmentAlert = AttachmentAlert(
                title: "Files Not Attached",
                message: "Mobidex could not copy the selected files into a readable upload location."
            )
        }
    }

    private func toggleAudioRecording() {
        if isRecordingAudio {
            stopAndTranscribeAudio()
        } else {
            startAudioRecording()
        }
    }

    private func startAudioRecording() {
        guard model.refreshOpenAIAPIKeyState() else {
            attachmentAlert = AttachmentAlert(
                title: "OpenAI API Key Required",
                message: "Add an OpenAI API key in Settings before recording audio."
            )
            return
        }
        Task { @MainActor in
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                attachmentAlert = AttachmentAlert(title: "Microphone Disabled", message: "Allow microphone access in Settings to record audio.")
                return
            }
            do {
                let recorder = try AudioComposerRecorder()
                try recorder.start()
                audioRecorder = recorder
                isRecordingAudio = true
            } catch {
                attachmentAlert = AttachmentAlert(title: "Recording Failed", message: error.localizedDescription)
            }
        }
    }

    private func stopAndTranscribeAudio() {
        guard let recorder = audioRecorder else { return }
        audioRecorder = nil
        isRecordingAudio = false
        let url = recorder.stop()
        let draftKey = composerDraftKey
        isTranscribingAudio = true
        Task {
            defer {
                try? FileManager.default.removeItem(at: url)
                isTranscribingAudio = false
            }
            do {
                let transcript = try await model.transcribeAudio(at: url)
                if composerDraftKey == draftKey {
                    let separator = composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
                    composerText += "\(separator)\(transcript)"
                    composerEditGeneration &+= 1
                    saveComposerDraft(for: draftKey)
                } else if let draftKey {
                    let existingDraft = composerDrafts[draftKey]
                    let existingText = existingDraft?.text ?? ""
                    let separator = existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
                    composerDrafts[draftKey] = ComposerDraft(
                        text: "\(existingText)\(separator)\(transcript)",
                        attachmentPaths: existingDraft?.attachmentPaths ?? []
                    )
                }
            } catch {
                attachmentAlert = AttachmentAlert(title: "Transcription Failed", message: error.localizedDescription)
            }
        }
    }

    private func updateRecordingIdleTimer(isRecording: Bool) {
        if isRecording {
            guard !didDisableIdleTimerForRecording else { return }
            idleTimerWasDisabledBeforeRecording = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            didDisableIdleTimerForRecording = true
            return
        }
        guard didDisableIdleTimerForRecording else { return }
        UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabledBeforeRecording
        didDisableIdleTimerForRecording = false
    }
}

private struct RecordingActivityBars: View {
    private let bars: [CGFloat] = [0.38, 0.78, 0.52, 0.92, 0.46]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(bars.indices, id: \.self) { index in
                    let phase = time * 5 + Double(index) * 0.85
                    let scale = bars[index] + CGFloat((sin(phase) + 1) * 0.22)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.red.opacity(0.85))
                        .frame(width: 4, height: 22)
                        .scaleEffect(x: 1, y: min(scale, 1), anchor: .center)
                }
            }
            .frame(width: 34, height: 24)
        }
        .accessibilityHidden(true)
    }
}

private final class AudioComposerRecorder {
    private let recorder: AVAudioRecorder
    private let audioSession = AVAudioSession.sharedInstance()
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobidex-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        )
    }

    func start() throws {
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)
        guard recorder.record() else {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw AudioComposerRecorderError.recordingDidNotStart
        }
    }

    func stop() -> URL {
        recorder.stop()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }
}

private enum AudioComposerRecorderError: LocalizedError {
    case recordingDidNotStart

    var errorDescription: String? {
        "Could not start audio recording."
    }
}

private struct ComposerDraft {
    var text: String
    var attachmentPaths: [String]
}

private struct QueuedMessagesSheet: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(model.queuedTurnInputs.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.preview)
                            .font(.body)
                            .lineLimit(4)
                        Text("Queued \(index + 1) of \(model.queuedTurnInputs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.deleteQueuedTurnInput(item.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task { await model.steerQueuedTurnInputNow(item.id) }
                        } label: {
                            Label("Steer Now", systemImage: "arrow.triangle.turn.up.right.circle")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            Task { await model.steerQueuedTurnInputNow(item.id) }
                        } label: {
                            Label("Steer Active Turn Now", systemImage: "arrow.triangle.turn.up.right.circle")
                        }
                        Button {
                            model.moveQueuedTurnInput(item.id, direction: -1)
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                        .disabled(index == 0)
                        Button {
                            model.moveQueuedTurnInput(item.id, direction: 1)
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                        .disabled(index == model.queuedTurnInputs.count - 1)
                        Button(role: .destructive) {
                            model.deleteQueuedTurnInput(item.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if model.queuedTurnInputs.isEmpty {
                    ContentUnavailableView("No Queued Messages", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
            }
            .navigationTitle("Queued Messages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ComposerAttachmentTile: View {
    let path: String
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AttachmentThumbnail(path: path, size: CGSize(width: 72, height: 72))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.45))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.secondary)
                    .background(Circle().fill(.black.opacity(0.22)))
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Remove attachment")
        }
        .frame(width: 72, height: 72)
    }
}

private struct AttachmentThumbnail: View {
    let path: String
    let size: CGSize

    var body: some View {
        Group {
            if AttachmentDisplay.isImagePath(path),
               FileManager.default.fileExists(atPath: path),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                    Image(systemName: AttachmentDisplay.isImagePath(path) ? "photo" : "doc")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

private struct UserMessageBodyView: View {
    let messageBody: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(UserMessageBodyPart.parts(from: messageBody)) { part in
                switch part.content {
                case .text(let text):
                    Text(text)
                case .attachment(let attachment):
                    MessageAttachmentTile(attachment: attachment)
                }
            }
        }
    }
}

private struct MessageAttachmentTile: View {
    let attachment: MessageAttachment

    var body: some View {
        HStack(spacing: 10) {
            AttachmentThumbnail(path: attachment.path, size: CGSize(width: 54, height: 54))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(attachment.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct MessageAttachment: Equatable {
    var kind: String
    var path: String

    var title: String {
        AttachmentDisplay.isImageKind(kind) || AttachmentDisplay.isImagePath(path) ? "Image attachment" : "Attachment"
    }

    var subtitle: String {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return filename.isEmpty ? path : filename
    }
}

private struct UserMessageBodyPart: Identifiable {
    enum Content {
        case text(String)
        case attachment(MessageAttachment)
    }

    var id: Int
    var content: Content

    static func parts(from body: String) -> [UserMessageBodyPart] {
        var parts: [UserMessageBodyPart] = []
        var textLines: [String] = []

        func flushText() {
            let text = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                parts.append(UserMessageBodyPart(id: parts.count, content: .text(text)))
            }
            textLines.removeAll()
        }

        for line in body.components(separatedBy: .newlines) {
            if let attachment = AttachmentDisplay.attachment(fromDisplayLine: line) {
                flushText()
                parts.append(UserMessageBodyPart(id: parts.count, content: .attachment(attachment)))
            } else {
                textLines.append(line)
            }
        }
        flushText()
        if parts.isEmpty, !body.isEmpty {
            parts.append(UserMessageBodyPart(id: 0, content: .text(body)))
        }
        return parts
    }
}

private enum AttachmentDisplay {
    static func attachment(fromDisplayLine line: String) -> MessageAttachment? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              trimmed.hasSuffix("]"),
              let separator = trimmed.firstIndex(of: ":")
        else {
            return nil
        }
        let kindStart = trimmed.index(after: trimmed.startIndex)
        let kind = String(trimmed[kindStart..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAttachmentKind(kind) else { return nil }
        let valueStart = trimmed.index(after: separator)
        let valueEnd = trimmed.index(before: trimmed.endIndex)
        let path = String(trimmed[valueStart..<valueEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return MessageAttachment(kind: kind, path: path)
    }

    static func isAttachmentKind(_ kind: String) -> Bool {
        let normalized = kind.lowercased()
        return normalized.contains("image") || normalized == "file" || normalized == "attachment"
    }

    static func isImageKind(_ kind: String) -> Bool {
        kind.lowercased().contains("image")
    }

    static func isImagePath(_ path: String) -> Bool {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "apng", "avif", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp":
            true
        default:
            false
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
            .frame(maxWidth: section.kind == .user ? 680 : .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            if section.kind != .user {
                EmptyView()
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
        if section.kind == .user {
            UserMessageBodyView(messageBody: section.body)
        } else if section.rendersMarkdown {
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
    private let markdown: String

    init(_ markdown: String, id: String) {
        self.markdown = markdown
    }

    var body: some View {
        SharedMarkdownView(markdown: markdown)
    }
}

private struct InlineMarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for run in ConversationInlineMarkdownParser.runs(from: text) {
            var value: AttributedString
            switch run {
            case .text(let text):
                value = AttributedString(text)
            case .code(let code):
                value = AttributedString(code)
                value.font = .system(.body, design: .monospaced)
                value.foregroundColor = .primary
            case .link(let label, let destination):
                value = AttributedString(label)
                value.foregroundColor = .accentColor
                if let url = ConversationInlineMarkdownParser.url(from: destination) {
                    value.link = url
                }
            }
            result += value
        }
        return result
    }
}

enum ConversationInlineMarkdownRun: Equatable {
    case text(String)
    case code(String)
    case link(label: String, destination: String)
}

enum ConversationInlineMarkdownParser {
    static func runs(from text: String) -> [ConversationInlineMarkdownRun] {
        var runs: [ConversationInlineMarkdownRun] = []
        var index = text.startIndex

        func appendText(_ value: String) {
            guard !value.isEmpty else { return }
            if case .text(let existing) = runs.last {
                runs[runs.count - 1] = .text(existing + value)
            } else {
                runs.append(.text(value))
            }
        }

        while index < text.endIndex {
            if text[index] == "`" {
                let contentStart = text.index(after: index)
                if let closing = text[contentStart...].firstIndex(of: "`") {
                    runs.append(.code(String(text[contentStart..<closing])))
                    index = text.index(after: closing)
                } else {
                    appendText(String(text[index...]))
                    break
                }
            } else if text[index] == "[",
                      let parsedLink = parseLink(in: text, from: index) {
                runs.append(.link(label: parsedLink.label, destination: parsedLink.destination))
                index = parsedLink.endIndex
            } else {
                let nextCode = text[index...].firstIndex(of: "`")
                let nextLink = text[index...].firstIndex(of: "[")
                let candidates = [nextCode, nextLink].compactMap { $0 }.filter { $0 > index }
                let next = candidates.min() ?? text.endIndex
                appendText(String(text[index..<next]))
                index = next
            }
        }

        return runs
    }

    static func url(from destination: String) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return nil
    }

    private static func parseLink(
        in text: String,
        from start: String.Index
    ) -> (label: String, destination: String, endIndex: String.Index)? {
        let labelStart = text.index(after: start)
        guard let labelEnd = text[labelStart...].firstIndex(of: "]"),
              labelEnd < text.index(before: text.endIndex)
        else {
            return nil
        }
        let openParen = text.index(after: labelEnd)
        guard openParen < text.endIndex, text[openParen] == "(" else {
            return nil
        }
        let destinationStart = text.index(after: openParen)
        guard let destinationEnd = text[destinationStart...].firstIndex(of: ")") else {
            return nil
        }
        let label = String(text[labelStart..<labelEnd])
        let destination = String(text[destinationStart..<destinationEnd])
        guard !label.isEmpty, !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return (label, destination, text.index(after: destinationEnd))
    }
}

private enum ConversationMarkdownBlock: Identifiable {
    case paragraph(String, String)
    case bulletList(String, [String])
    case orderedList(String, [String])
    case codeBlock(String, String)

    var id: String {
        switch self {
        case .paragraph(let id, _), .bulletList(let id, _), .orderedList(let id, _), .codeBlock(let id, _):
            id
        }
    }
}

private enum ConversationMarkdownParser {
    static func blocks(from body: String) -> [ConversationMarkdownBlock] {
        ConversationTextPresentation.markdownBlocks(from: ConversationTextPresentation.displayBody(from: body))
            .enumerated()
            .map { offset, block in
                parseBlock(block, offset: offset)
            }
    }

    private static func parseBlock(_ block: String, offset: Int) -> ConversationMarkdownBlock {
        let id = "\(offset)-\(stableHash(block))"
        let lines = block
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if let code = fencedCode(from: lines) {
            return .codeBlock(id, code)
        }

        let nonEmptyLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let bulletItems = nonEmptyLines.compactMap(bulletItem(from:))
        if !bulletItems.isEmpty, bulletItems.count == nonEmptyLines.count {
            return .bulletList(id, bulletItems)
        }

        let orderedItems = nonEmptyLines.compactMap(orderedItem(from:))
        if !orderedItems.isEmpty, orderedItems.count == nonEmptyLines.count {
            return .orderedList(id, orderedItems)
        }

        return .paragraph(id, paragraphText(from: lines))
    }

    private static func fencedCode(from lines: [String]) -> String? {
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.hasPrefix("```") || first.hasPrefix("~~~")
        else {
            return nil
        }
        var codeLines = lines
        codeLines.removeFirst()
        if let last = codeLines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           last.hasPrefix("```") || last.hasPrefix("~~~") {
            codeLines.removeLast()
        }
        return codeLines.joined(separator: "\n")
    }

    private static func bulletItem(from line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func orderedItem(from line: String) -> String? {
        guard let marker = line.firstIndex(of: ".") else { return nil }
        let number = line[..<marker]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let afterMarker = line[line.index(after: marker)...]
        guard afterMarker.first == " " else { return nil }
        return String(afterMarker.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func paragraphText(from lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
