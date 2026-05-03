import SwiftUI

@main
struct MobidexApp: App {
    @StateObject private var model: AppViewModel
    @State private var didStartLaunchSmoke = false

    init() {
        _model = StateObject(wrappedValue: Self.makeModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task {
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
                sshService: CitadelSSHService()
            )
        }
        return AppViewModel(
            repository: UserDefaultsServerRepository(),
            credentialStore: KeychainCredentialStore(),
            sshService: CitadelSSHService()
        )
    }
}
