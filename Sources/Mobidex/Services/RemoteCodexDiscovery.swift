import Foundation

enum RemoteCodexDiscovery {
    static var shellCommand: String {
        SharedKMPBridge.remoteCodexDiscoveryShellCommand
    }

    static func shellCommand(targetShellRCFile: String) -> String {
        SharedKMPBridge.remoteCodexDiscoveryShellCommand(targetShellRCFile: targetShellRCFile)
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
