import SwiftUI

struct ServerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppViewModel

    private let original: ServerRecord?
    @State private var displayName: String
    @State private var host: String
    @State private var port: Int
    @State private var username: String
    @State private var codexPath: String
    @State private var executionPath: String
    @State private var backendType: BackendType
    @State private var acpLaunchCommand: String
    @State private var authMethod: ServerAuthMethod
    @State private var password: String
    @State private var privateKey: String
    @State private var privateKeyPassphrase: String
    @State private var revealPrivateKey: Bool
    @State private var credentialLoaded: Bool
    @State private var credentialFieldsWereEdited = false
    @State private var isHydratingCredential = false
    @State private var isSaving = false
    @State private var validationMessage: String?

    init(server: ServerRecord?) {
        original = server
        _displayName = State(initialValue: server?.displayName ?? "")
        _host = State(initialValue: server?.host ?? "")
        _port = State(initialValue: server?.port ?? 22)
        _username = State(initialValue: server?.username ?? "")
        _codexPath = State(initialValue: server?.codexPath ?? SharedKMPBridge.defaultCodexPath)
        _executionPath = State(initialValue: server?.executionPath ?? SharedKMPBridge.defaultExecutionPath)
        _backendType = State(initialValue: server?.backendType ?? .codexAppServer)
        _acpLaunchCommand = State(initialValue: server?.acpLaunchCommand ?? SharedKMPBridge.defaultAcpLaunchCommand)
        _authMethod = State(initialValue: server?.authMethod ?? .password)
        _password = State(initialValue: "")
        _privateKey = State(initialValue: "")
        _privateKeyPassphrase = State(initialValue: "")
        _revealPrivateKey = State(initialValue: server == nil)
        _credentialLoaded = State(initialValue: server == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $displayName)
                    TextField("Host", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Stepper(value: $port, in: 1...65_535) {
                        Text("Port \(port)")
                    }
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Picker("Agent Protocol", selection: $backendType) {
                        ForEach(BackendType.allCases, id: \.self) { backend in
                            Text(backend.label).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(backendType.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Agent Protocol")
                }

                Section {
                    TextField("Execution Path", text: $executionPath, prompt: Text(SharedKMPBridge.defaultExecutionPath))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("executionPathField")
                } header: {
                    Text("Command Environment")
                } footer: {
                    Text("Mobidex injects this PATH for SSH commands. Shell startup files are not sourced.")
                }

                if backendType == .codexAppServer {
                    Section {
                        TextField("Full Path to Codex", text: $codexPath, prompt: Text("~/.bun/bin/codex"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("codexPathField")
                    } header: {
                        Text("Codex Binary Path")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Use the full remote executable path when possible. Mobidex uses this to attach through Codex's official Unix control socket, or to start that socket if needed.")
                            Text("Examples: ~/.bun/bin/codex, /home/ubuntu/.bun/bin/codex, /usr/local/bin/codex.")
                        }
                    }
                } else {
                    Section {
                        TextField("ACP Launch Command", text: $acpLaunchCommand, prompt: Text(SharedKMPBridge.defaultAcpLaunchCommand), axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(2...4)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("acpLaunchCommandField")
                        HStack(spacing: 12) {
                            Button("Grok") {
                                acpLaunchCommand = SharedKMPBridge.acpGrokLaunchCommand
                            }
                            .accessibilityIdentifier("acpPresetGrokButton")
                            Button("Claude") {
                                acpLaunchCommand = SharedKMPBridge.acpClaudeLaunchCommand
                            }
                            .accessibilityIdentifier("acpPresetClaudeButton")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } header: {
                        Text("ACP Launch Command")
                    } footer: {
                        Text("Mobidex runs this remote command over SSH and expects ACP JSON-RPC over stdio. Use a preset or any ACP-compatible agent command. The agent reads its own login from the remote host (e.g. `grok` login or `claude /login`).")
                    }
                }

                Section("Authentication") {
                    Picker("Method", selection: $authMethod) {
                        ForEach(ServerAuthMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if authMethod == .password {
                        SecureField("Password", text: $password)
                    } else {
                        HStack {
                            Text("OpenSSH Private Key")
                            Spacer()
                            Button(revealPrivateKey ? "Hide" : "Show") {
                                revealPrivateKey.toggle()
                            }
                        }
                        if revealPrivateKey {
                            TextEditor(text: $privateKey)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(minHeight: 170)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("OpenSSH Private Key", text: $privateKey)
                                .font(.system(.footnote, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        SecureField("Passphrase", text: $privateKeyPassphrase)
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("serverValidationMessage")
                    }
                }
            }
            .navigationTitle(original == nil ? "Add Server" : "Edit Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!credentialLoaded || isSaving)
                }
            }
            .task {
                guard let original else {
                    credentialLoaded = true
                    return
                }
                let credential = await model.loadCredential(for: original.id)
                guard !Task.isCancelled else { return }
                guard !credentialFieldsWereEdited else {
                    credentialLoaded = true
                    return
                }
                isHydratingCredential = true
                password = credential.password ?? ""
                privateKey = credential.privateKeyPEM ?? ""
                privateKeyPassphrase = credential.privateKeyPassphrase ?? ""
                isHydratingCredential = false
                credentialLoaded = true
            }
            .onChange(of: password) { _, _ in markCredentialEdited() }
            .onChange(of: privateKey) { _, _ in markCredentialEdited() }
            .onChange(of: privateKeyPassphrase) { _, _ in markCredentialEdited() }
        }
    }

    private func markCredentialEdited() {
        guard !isHydratingCredential else { return }
        credentialFieldsWereEdited = true
    }

    private var validationError: String? {
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the SSH host for this server."
        }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the SSH username for this server."
        }
        if !credentialIsPresent {
            switch authMethod {
            case .password:
                return "Enter the SSH password for this server."
            case .privateKey:
                return "Paste an OpenSSH private key for this server."
            }
        }
        return nil
    }

    private var credentialIsPresent: Bool {
        switch authMethod {
        case .password:
            !password.isEmpty
        case .privateKey:
            !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else {
            return
        }
        if let validationError {
            validationMessage = validationError
            return
        }
        validationMessage = nil
        isSaving = true
        defer { isSaving = false }

        let id = original?.id ?? UUID()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = ServerRecord(
            id: id,
            displayName: name.isEmpty ? host : name,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            codexPath: codexPath,
            executionPath: executionPath,
            acpLaunchCommand: acpLaunchCommand,
            authMethod: authMethod,
            projects: original?.projects ?? [],
            createdAt: original?.createdAt ?? .now,
            updatedAt: .now,
            backendType: backendType
        )
        let credential = SSHCredential(
            password: authMethod == .password ? password : nil,
            privateKeyPEM: authMethod == .privateKey ? privateKey : nil,
            privateKeyPassphrase: authMethod == .privateKey ? privateKeyPassphrase : nil
        )
        if await model.saveServer(server, credential: credential) {
            dismiss()
        } else {
            validationMessage = model.statusMessage ?? "Mobidex could not save this server."
        }
    }
}
