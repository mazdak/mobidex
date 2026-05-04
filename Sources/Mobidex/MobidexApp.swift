import SwiftUI

@main
struct MobidexApp: App {
    @StateObject private var model: AppViewModel
    @State private var didStartLaunchSmoke = false
    @State private var showSplash: Bool

    init() {
        _model = StateObject(wrappedValue: Self.makeModel())
        _showSplash = State(initialValue: Self.shouldShowSplash)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(model)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
                .task {
                    await prepareApp()
                    guard !didStartLaunchSmoke else { return }
                    didStartLaunchSmoke = true
                    await MobidexLaunchSmoke.runIfRequested(model: model)
            }
        }
    }

    private static func makeModel() -> AppViewModel {
        if ProcessInfo.processInfo.environment["MOBIDEX_SMOKE"] == "1" {
            return AppViewModel(
                repository: InMemoryServerRepository(),
                credentialStore: InMemoryCredentialStore(),
                sshService: CitadelSSHService(),
                loadServersOnInit: false
            )
        }
        return AppViewModel(
            repository: UserDefaultsServerRepository(),
            credentialStore: KeychainCredentialStore(),
            sshService: CitadelSSHService(),
            loadServersOnInit: false
        )
    }

    private static var shouldShowSplash: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["MOBIDEX_SMOKE"] != "1"
            && environment["MOBIDEX_DISABLE_SPLASH"] != "1"
    }

    @MainActor
    private func dismissSplashIfNeeded() async {
        guard showSplash else { return }
        try? await Task.sleep(nanoseconds: 850_000_000)
        withAnimation(.easeOut(duration: 0.22)) {
            showSplash = false
        }
    }

    @MainActor
    private func prepareApp() async {
        async let loadServers: Void = model.loadServersIfNeeded()
        await dismissSplashIfNeeded()
        await loadServers
    }
}
