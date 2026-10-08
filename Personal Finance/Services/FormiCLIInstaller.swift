#if os(macOS)
import AppKit
import Darwin

@MainActor
enum FormiCLIInstaller {
    static var commandName: String {
        #if DEBUG
        "formi-debug"
        #else
        "formi"
        #endif
    }
    static var channel: String { commandName == "formi-debug" ? "debug" : "release" }
    static let installationPathKey = "formi.cli.installation.path"
    private static let launcherMarker = "# Formi CLI launcher — installed explicitly from Formi settings."

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Called only by the settings button. The panel grants access to the chosen folder.
    static func install(executable: URL, previousPath: String?) async throws -> URL? {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw Failure(message: "La CLI non è presente in questa copia di Formi. Usa una build Mac che la includa.")
        }
        let panel = NSOpenPanel()
        panel.title = "Installa la CLI di Formi"
        panel.message = "Scegli una cartella in cui installare il comando \(commandName). Usa una cartella nel PATH, oppure aggiungila al PATH dopo l'installazione."
        panel.prompt = "Installa"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true
        if let previousPath, !previousPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: previousPath).deletingLastPathComponent()
        } else if let user = getpwuid(getuid()), let directory = user.pointee.pw_dir {
            // NSHomeDirectory() points into the app container when sandboxed.
            let home = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
            panel.directoryURL = home
        }
        let result: NSApplication.ModalResponse
        if let window = NSApp.keyWindow { result = await panel.beginSheetModal(for: window) }
        else { result = panel.runModal() }
        guard result == .OK, let directory = panel.url else { return nil }
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
        let destination = directory.appendingPathComponent(commandName)
        try writeLauncher(to: destination, executable: executable)
        return destination
    }

    /// Writes only the explicitly selected destination. No profile or PATH edits.
    static func writeLauncher(to destination: URL, executable: URL) throws {
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resolvedDestination = destination.resolvingSymlinksInPath().standardizedFileURL
        let resolvedApp = app.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedDestination.path != resolvedApp.path,
              !resolvedDestination.path.hasPrefix(resolvedApp.path + "/") else {
            throw Failure(message: "Scegli una posizione esterna all'app per installare il comando.")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            let existing = try String(contentsOf: destination, encoding: .utf8)
            guard existing.hasPrefix("#!/bin/sh\n" + launcherMarker + "\n") else {
                throw Failure(message: "Esiste già un file formi che non è stato installato da Formi. Scegli un'altra cartella.")
            }
        }
        let command = shellQuote(executable.path)
        let script = """
        #!/bin/sh
        \(launcherMarker)
        if [ ! -x \(command) ]; then
            echo 'La CLI di Formi non è più disponibile in questa posizione. Reinstallala dalle impostazioni di Formi.' >&2
            exit 1
        fi
        exec \(command) --expect-channel \(channel) "$@"

        """
        try Data(script.utf8).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: destination.path)
    }
}
#endif
