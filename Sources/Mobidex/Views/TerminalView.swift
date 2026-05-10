import SwiftUI

struct TerminalView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var outputText = "Opening terminal...\n"
    @State private var terminal: RemoteTerminalSession?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(outputText.isEmpty ? " " : outputText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .id("terminal-output")
                    }
                    .background(Color.black)
                    .onChange(of: outputText) { _, _ in
                        proxy.scrollTo("terminal-output", anchor: .bottom)
                    }
                }

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        terminalControl("Ctrl-C", bytes: [0x03])
                        terminalControl("Esc", bytes: [0x1B])
                        terminalControl("Tab", bytes: [0x09])
                        Button("Clear") { outputText = "" }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        Text(">")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                        TextField("Input", text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .onSubmit { sendLine() }
                        Button {
                            sendLine()
                        } label: {
                            Image(systemName: "return")
                        }
                        .disabled(terminal == nil || input.isEmpty)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await openTerminal()
            }
            .onDisappear {
                let terminal = terminal
                Task { await terminal?.close() }
            }
        }
    }

    private func terminalControl(_ title: String, bytes: [UInt8]) -> some View {
        Button(title) {
            send(Data(bytes))
        }
        .buttonStyle(.bordered)
        .disabled(terminal == nil)
    }

    private func openTerminal() async {
        do {
            let session = try await model.openTerminalSession(columns: 80, rows: 24)
            terminal = session
            defer {
                terminal = nil
                Task { await session.close() }
            }
            outputText = ""
            do {
                for try await data in session.output {
                    outputText.append(String(decoding: data, as: UTF8.self))
                    if outputText.count > 80_000 {
                        outputText = String(outputText.suffix(60_000))
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                appendSystemLine(error.localizedDescription)
            }
        } catch {
            guard !Task.isCancelled else { return }
            appendSystemLine(error.localizedDescription)
        }
    }

    private func sendLine() {
        guard !input.isEmpty else { return }
        let line = input
        input = ""
        send(Data("\(line)\n".utf8))
    }

    private func send(_ data: Data) {
        guard let terminal else { return }
        Task {
            do {
                try await terminal.write(data)
            } catch {
                appendSystemLine(error.localizedDescription)
            }
        }
    }

    private func appendSystemLine(_ line: String) {
        outputText.append("\n\(line)\n")
    }
}
