import Foundation

enum RemoteCodexDiscovery {
    static var shellCommand: String {
        SharedKMPBridge.remoteCodexDiscoveryShellCommand
    }

    static func shellCommand(executionPath: String) -> String {
        SharedKMPBridge.remoteCodexDiscoveryShellCommand(executionPath: executionPath)
    }

    static var pythonSource: String {
        SharedKMPBridge.remoteCodexDiscoveryPythonSource
    }

    static func decodeProjects(from output: String) throws -> [RemoteProject] {
        do {
            return try SharedKMPBridge.decodeRemoteProjects(from: output)
        } catch {
            throw SSHServiceError.invalidDiscoveryOutput(error.localizedDescription)
        }
    }
}
