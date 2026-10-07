import SwiftUI
import LocalAuthentication

@MainActor
protocol DeviceAuthenticating: AnyObject {
    func authenticate(reason: String) async throws -> Bool
    func cancel()
}

@MainActor
final class SystemDeviceAuthentication: DeviceAuthenticating {
    private var context: LAContext?
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Annulla"
        self.context = context
        defer { if self.context === context { self.context = nil } }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? NSError(domain: LAError.errorDomain, code: LAError.passcodeNotSet.rawValue)
        }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
    func cancel() { context?.invalidate(); context = nil }
}

@MainActor
@Observable
final class AppLock {
    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?
    private let onPrivacyChanged: (@MainActor (Bool) -> Void)?
    private let defaults: UserDefaults
    private let authenticator: any DeviceAuthenticating
    private(set) var phase: ScenePhase = .active
    private(set) var hasUnlockedInSession: Bool
    var shouldConceal: Bool { isEnabled && (isLocked || phase != .active) }
    private var unlockOnActivation = false
    private var requestID: UUID?
    static let preferenceKey = "forgia.deviceAuthentication.enabled"

    init(defaults: UserDefaults = .standard, authenticator: (any DeviceAuthenticating)? = nil, onPrivacyChanged: (@MainActor (Bool) -> Void)? = nil) {
        self.onPrivacyChanged = onPrivacyChanged
        self.defaults = defaults
        self.authenticator = authenticator ?? SystemDeviceAuthentication()
        let enabled = defaults.bool(forKey: Self.preferenceKey)
        isEnabled = enabled
        isLocked = enabled
        hasUnlockedInSession = !enabled
    }

    func sceneChanged(_ phase: ScenePhase) {
        self.phase = phase
        if phase == .active, unlockOnActivation {
            unlockOnActivation = false
            isLocked = false
            hasUnlockedInSession = true
        } else if phase == .background {
            unlockOnActivation = false
            requestID = nil
            authenticator.cancel()
            isAuthenticating = false
            if isEnabled { isLocked = true }
        }
        #if os(macOS)
        // Switching away from a Mac window has no iOS-style background transition.
        if phase == .inactive, !isAuthenticating, isEnabled { isLocked = true }
        #endif
    }

    func unlock() async { await verify(enable: nil) }
    func setEnabled(_ enabled: Bool) async { await verify(enable: enabled) }
    func clearError() { errorMessage = nil }

    private func verify(enable: Bool?) async {
        guard !isAuthenticating else { return }
        let id = UUID()
        requestID = id
        isAuthenticating = true
        errorMessage = nil
        do {
            let accepted = try await authenticator.authenticate(reason: enable == nil
                ? "Sblocca Formi per accedere ai tuoi dati finanziari."
                : "Conferma la modifica del blocco di Formi.")
            guard requestID == id else { return }
            guard accepted, !Task.isCancelled else {
                isAuthenticating = false
                requestID = nil
                return
            }
            if let enable {
                if enable { onPrivacyChanged?(true) }
                isEnabled = enable
                defaults.set(enable, forKey: Self.preferenceKey)
            }
            isLocked = isEnabled && phase != .active
            unlockOnActivation = isLocked
            if !isLocked { hasUnlockedInSession = true }
        } catch {
            guard requestID == id else { return }
            errorMessage = "Autenticazione non completata. Riprova con Face ID, Touch ID o le credenziali del dispositivo."
        }
        requestID = nil
        isAuthenticating = false
    }
}

struct AppLockScreen: View {
    @Environment(AppLock.self) private var lock
    var body: some View {
        VStack(spacing: 20) {
            FormiLogo(size: 72)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ForgiaPalette.onAccent)
                        .padding(7)
                        .background(ForgiaPalette.accent, in: Circle())
                        .overlay(Circle().stroke(ForgiaPalette.canvas, lineWidth: 3))
                        .offset(x: 8, y: 8)
                        .accessibilityHidden(true)
                }
            Text("Formi è bloccata").font(.title.bold())
            Text("Autenticati per accedere ai tuoi dati.").foregroundStyle(.secondary)
            if let error = lock.errorMessage {
                Text(error).font(.caption).multilineTextAlignment(.center)
            }
            Button("Sblocca") {
                #if os(macOS)
                NSApplication.shared.activate()
                #endif
                Task { await lock.unlock() }
            }
                .buttonStyle(.borderedProminent)
                .disabled(lock.isAuthenticating)
            if lock.isAuthenticating { ProgressView() }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ForgiaPalette.canvas)
        .accessibilityIdentifier("app-lock-screen")
    }
}

struct AppLockSettingsSection: View {
    @Environment(AppLock.self) private var lock
    var body: some View {
        Section {
            Toggle("Blocca Formi", isOn: Binding(
                get: { lock.isEnabled },
                set: { enabled in Task { await lock.setEnabled(enabled) } }
            ))
            .disabled(lock.isAuthenticating)
            .accessibilityIdentifier("app-lock-toggle")
            if let error = lock.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Richiede Face ID, Touch ID o le credenziali del dispositivo all'apertura e quando lasci l'app. L'attivazione e la disattivazione richiedono conferma. Le bozze restano in memoria durante il blocco; vengono perse se chiudi l’app o il sistema la termina.")
        }
    }
}
