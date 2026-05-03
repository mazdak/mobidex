import SwiftUI

struct ConversationView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var composerText = ""
    private let conversationBottomID = "conversationBottom"

    var body: some View {
        VStack(spacing: 0) {
            if let thread = model.selectedThread {
                header(thread)
                Divider()
                timeline
                composer
            } else if let project = model.selectedProject {
                projectHeader(project)
                Divider()
                ContentUnavailableView("No Sessions", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a Session", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model.selectedThread?.title ?? model.selectedProject?.displayName ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
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
            Button {
                Task { await model.startNewThread() }
            } label: {
                Label("New Thread", systemImage: "plus.bubble")
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy || !model.canSendMessage)
            .accessibilityIdentifier("newThreadButton")
            Label(thread.status.sessionLabel, systemImage: thread.status.isActive ? "dot.radiowaves.left.and.right" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(thread.status.isActive ? .green : .secondary)
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
                Task { await model.startNewThread() }
            } label: {
                Label("New Thread", systemImage: "plus.bubble")
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy || !model.canSendMessage)
            .accessibilityIdentifier("newThreadButton")
        }
        .padding()
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
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
                    }
                    .padding()
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
                scrollToConversationBottom(proxy)
            }
            .onChange(of: model.conversationRevision) { _, _ in
                scrollToConversationBottom(proxy)
            }
            .onChange(of: model.isSelectedThreadLoading) { _, loading in
                if !loading {
                    scrollToConversationBottom(proxy)
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
                    .accessibilityIdentifier("messageComposer")

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
        composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.canSendMessage || model.isBusy
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

            microphoneIcon

            sendButton
        }
    }

    private var compactComposerControlRow: some View {
        HStack(spacing: 12) {
            attachmentIcon

            accessLabel(showText: false)

            Spacer(minLength: 6)

            contextIndicator
            Text("5.5")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .accessibilityLabel("Model GPT-5.5 Medium")

            microphoneIcon

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
        Image(systemName: "plus")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    private var microphoneIcon: some View {
        Image(systemName: "mic")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    private func accessLabel(showText: Bool) -> some View {
        Label {
            if showText {
                Text("Full access")
            }
        } icon: {
            Image(systemName: "exclamationmark.shield")
        }
        .font(.subheadline)
        .foregroundStyle(.orange)
        .accessibilityLabel("Full access")
    }

    private func modelLabel(showReasoning: Bool) -> some View {
        HStack(spacing: 6) {
            Text("5.5")
                .fontWeight(.medium)
            if showReasoning {
                Text("Medium")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .accessibilityLabel("Model GPT-5.5 Medium")
    }

    private var sendButton: some View {
        Button {
            let text = composerText
            composerText = ""
            Task { await model.sendComposerText(text) }
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
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                .frame(width: 18, height: 18)
            Circle()
                .trim(from: 0, to: model.isBusy ? 0.72 : 0.18)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 18, height: 18)
        }
        .accessibilityLabel("Context window")
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

    var body: some View {
        HStack {
            if section.kind == .user {
                Spacer(minLength: 36)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .foregroundStyle(accent)
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let status = section.status, !status.isEmpty {
                        Text(status)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.14), in: Capsule())
                    }
                }
                if !section.body.isEmpty {
                    Text(section.body)
                        .font(bodyFont)
                        .textSelection(.enabled)
                }
                if let detail = section.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .frame(maxWidth: 680, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            if section.kind != .user {
                Spacer(minLength: 36)
            }
        }
    }

    private var bodyFont: Font {
        switch section.kind {
        case .command, .fileChange:
            .system(.footnote, design: .monospaced)
        default:
            .body
        }
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
