import AppIntents
import Foundation
import FinanceCore

struct CaptureBankNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Acquisisci notifica bancaria"
    static let description = IntentDescription("Conserva il testo di una notifica in Da approvare. Nessun saldo o budget cambia prima dell’approvazione in Formi.")
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "Testo della notifica") var text: String
    @Parameter(title: "Banca o app di origine") var bank: String?
    @Parameter(title: "Nome del conto di destinazione") var destination: String?
    // Optional source event ID for automations that can supply a stable identifier.
    @Parameter(title: "Identificativo dell’evento (facoltativo)") var eventID: String?
    static var parameterSummary: some ParameterSummary {
        Summary("Acquisisci notifica bancaria \(\.$text)") { \.$bank; \.$destination; \.$eventID }
    }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 30_000 else { throw CaptureIntentFailure.invalidText }
        let id: UUID
        if let eventID, !eventID.isEmpty {
            guard let supplied = UUID(uuidString: eventID) else { throw CaptureIntentFailure.invalidID }
            id = supplied
        } else { id = UUID() }
        do {
            try CaptureStore.enqueue(PendingCapture(id: id, source: "notification", sourceName: String((bank ?? "Notifica bancaria").prefix(160)), text: trimmed, destinationName: String((destination ?? "").prefix(160))))
        } catch CaptureStore.Failure.reusedID { throw CaptureIntentFailure.reusedID }
        catch {
            throw CaptureIntentFailure.storageUnavailable
        }
        return .result(dialog: "Notifica acquisita. Controllala in Da approvare in Formi.")
    }
}

enum CaptureIntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case invalidText, invalidID, reusedID, storageUnavailable
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidText: "Passa il testo della notifica, entro 30.000 caratteri."
        case .storageUnavailable: "La notifica non è stata conservata. Apri Formi e riprova l’acquisizione."
        case .reusedID: "L’identificativo dell’evento appartiene già a un’altra notifica. Usa un UUID diverso."
        case .invalidID: "L’identificativo dell’evento deve essere un UUID. Puoi lasciare il campo vuoto."
        }
    }
}
