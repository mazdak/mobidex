import SwiftUI
import WebKit

struct TerminalView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var terminal: RemoteTerminalSession?
    @State private var webView: WKWebView?
    @State private var terminalReady = false
    @State private var pendingOutput: [String] = ["Opening terminal...\n".base64EncodedForJavaScript()]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TerminalWebView(
                    onReady: {
                        terminalReady = true
                        flushPendingOutput()
                    },
                    onInput: { data in
                        send(Data(data.utf8))
                    },
                    onResize: { columns, rows in
                        resize(columns: columns, rows: rows)
                    },
                    onError: { message in
                        appendSystemLine(message)
                    },
                    onWebViewReady: { view in
                        webView = view
                        if terminalReady {
                            flushPendingOutput()
                        }
                    }
                )
                .background(Color.black)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        terminalControl("Ctrl-C", text: "\u{03}")
                        terminalControl("Esc", text: "\u{1B}")
                        terminalControl("Tab", text: "\t")
                        Button("Clear") { evaluateTerminalJavaScript("window.mobidexTerminal?.clear()") }
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

    private func terminalControl(_ title: String, text: String) -> some View {
        Button(title) {
            sendThroughTerminalBridge(text)
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
            clearOpeningLine()
            do {
                for try await data in session.output {
                    writeToTerminal(data.base64EncodedString())
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
        sendThroughTerminalBridge("\(line)\n")
    }

    private func sendThroughTerminalBridge(_ text: String) {
        guard terminalReady else {
            send(Data(text.utf8))
            return
        }
        evaluateTerminalJavaScript("window.mobidexTerminal?.send(\(text.javaScriptStringLiteral()))")
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

    private func resize(columns: Int, rows: Int) {
        guard let terminal else { return }
        Task {
            try? await terminal.resize(columns: columns, rows: rows)
        }
    }

    private func clearOpeningLine() {
        pendingOutput.removeAll()
        if terminalReady {
            evaluateTerminalJavaScript("window.mobidexTerminal?.clear()")
        }
    }

    private func appendSystemLine(_ line: String) {
        writeToTerminal("\n\(line)\n".data(using: .utf8)?.base64EncodedString() ?? "")
    }

    private func writeToTerminal(_ base64: String) {
        guard terminalReady else {
            pendingOutput.append(base64)
            return
        }
        evaluateTerminalJavaScript("window.mobidexTerminal?.writeBase64(\(base64.javaScriptStringLiteral()))")
    }

    private func flushPendingOutput() {
        guard webView != nil else { return }
        let queued = pendingOutput
        pendingOutput.removeAll()
        for base64 in queued {
            writeToTerminal(base64)
        }
        evaluateTerminalJavaScript("window.mobidexTerminal?.focus()")
    }

    private func evaluateTerminalJavaScript(_ script: String) {
        webView?.evaluateJavaScript(script)
    }
}

private struct TerminalWebView: UIViewRepresentable {
    var onReady: () -> Void
    var onInput: (String) -> Void
    var onResize: (Int, Int) -> Void
    var onError: (String) -> Void
    var onWebViewReady: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onInput: onInput, onResize: onResize, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "mobidexTerminal")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.keyboardDismissMode = .interactive

        if let html = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "TerminalWeb") {
            webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        } else {
            onError("Terminal web assets are missing from the app bundle.")
        }

        DispatchQueue.main.async {
            onWebViewReady(webView)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onReady: () -> Void
        var onInput: (String) -> Void
        var onResize: (Int, Int) -> Void
        var onError: (String) -> Void

        init(onReady: @escaping () -> Void, onInput: @escaping (String) -> Void, onResize: @escaping (Int, Int) -> Void, onError: @escaping (String) -> Void) {
            self.onReady = onReady
            self.onInput = onInput
            self.onResize = onResize
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                onReady()
            case "input":
                if let data = body["data"] as? String {
                    onInput(data)
                }
            case "resize":
                if let columns = body["cols"] as? Int, let rows = body["rows"] as? Int {
                    onResize(columns, rows)
                }
            case "error":
                if let error = body["message"] as? String {
                    onError(error)
                }
            default:
                break
            }
        }
    }
}

private extension String {
    func javaScriptStringLiteral() -> String {
        guard let data = try? JSONEncoder().encode(self), let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }

    func base64EncodedForJavaScript() -> String {
        Data(utf8).base64EncodedString()
    }
}
