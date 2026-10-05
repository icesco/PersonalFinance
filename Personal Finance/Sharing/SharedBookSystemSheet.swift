import SwiftUI
import CloudKit
import FinanceCore

#if os(iOS)
import UIKit
struct SharedBookSystemSheet: UIViewControllerRepresentable {
    let share: CKShare
    let title: String
    let onStatus: (String) -> Void
    let onStopSharing: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(title: title, onStatus: onStatus, onStopSharing: onStopSharing) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: FinanceCoreModule.cloudKitContainerIdentifier))
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let onStatus: (String) -> Void
        let onStopSharing: () -> Void
        init(title: String, onStatus: @escaping (String) -> Void, onStopSharing: @escaping () -> Void) { self.title = title; self.onStatus = onStatus; self.onStopSharing = onStopSharing }
        func itemTitle(for controller: UICloudSharingController) -> String? { title }
        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            onStatus("Invito non confermato. Riapri la gestione degli invitati per verificarlo.")
        }
        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) { onStatus("Impostazioni di condivisione aggiornate.") }
        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) { onStopSharing() }
    }
}
#elseif os(macOS)
import AppKit
struct SharedBookSystemSheet: View {
    let share: CKShare
    let title: String
    let onStatus: (String) -> Void
    let onStopSharing: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 18) {
            Text(title).font(.title2)
            Text("Gestisci le persone che possono accedere al libro tramite iCloud.")
            MacCloudSharingButton(share: share, onStatus: onStatus, onStopSharing: onStopSharing).frame(width: 220, height: 32)
            Button("Chiudi") { dismiss() }
        }.padding(28).frame(width: 400)
    }
}
private struct MacCloudSharingButton: NSViewRepresentable {
    let share: CKShare
    let onStatus: (String) -> Void
    let onStopSharing: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(share: share, onStatus: onStatus, onStopSharing: onStopSharing) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Gestisci invitati", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.bezelStyle = .rounded
        return button
    }
    func updateNSView(_ view: NSButton, context: Context) {}
    final class Coordinator: NSObject, NSCloudSharingServiceDelegate {
        let share: CKShare
        let onStatus: (String) -> Void
        let onStopSharing: () -> Void
        var service: NSSharingService?
        init(share: CKShare, onStatus: @escaping (String) -> Void, onStopSharing: @escaping () -> Void) { self.share = share; self.onStatus = onStatus; self.onStopSharing = onStopSharing }
        @objc func open(_ sender: NSButton) {
            let provider = NSItemProvider()
            provider.registerCloudKitShare(share, container: CKContainer(identifier: FinanceCoreModule.cloudKitContainerIdentifier))
            guard let service = NSSharingService(named: .cloudSharing), service.canPerform(withItems: [provider]) else {
                onStatus("La gestione degli invitati non è disponibile. Riprova dopo aver verificato l’accesso a iCloud.")
                return
            }
            self.service = service; service.delegate = self
            service.perform(withItems: [provider])
        }
        func options(for sharingService: NSSharingService, share provider: NSItemProvider) -> NSSharingService.CloudKitOptions {
            [.allowPrivate, .allowReadWrite]
        }
        func sharingService(_ sharingService: NSSharingService, didSave share: CKShare) { onStatus("Impostazioni di condivisione aggiornate.") }
        func sharingService(_ sharingService: NSSharingService, didStopSharing share: CKShare) { onStopSharing() }
        func sharingService(_ sharingService: NSSharingService, didCompleteForItems items: [Any], error: (any Error)?) {
            if error != nil { onStatus("Invito non confermato. Riapri la gestione degli invitati per verificarlo.") }
        }
    }
}
#endif
