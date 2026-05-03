import SwiftUI

struct ConversationView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var composerText = ""

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
            Label(thread.status.label, systemImage: thread.status.isActive ? "dot.radiowaves.left.and.right" : "circle")
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
                }
                .padding()
            }
            .onChange(of: model.conversationSections.count) { _, _ in
                if let last = model.conversationSections.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Codex", text: $composerText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .accessibilityIdentifier("messageComposer")
            Button {
                let text = composerText
                composerText = ""
                Task { await model.sendComposerText(text) }
            } label: {
                Image(systemName: "paperplane.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.canSendMessage || model.isBusy)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("sendButton")
        }
        .padding()
        .background(.bar)
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
