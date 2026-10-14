import AppIntents
import Foundation
import FinanceCore

struct CaptureBankNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Acquisisci notifica bancaria"
    static let description = IntentDescription("Conserva il testo di una notifica in Da approvare. Nessun saldo o budget cambia prima dell’approvazione in Formi.")
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "Titolo") var notificationTitle: String?
    @Parameter(title: "Sottotitolo") var subtitle: String?
    @Parameter(title: "Corpo") var text: String?
    @Parameter(title: "Data") var notificationDate: Date?
    @Parameter(title: "Banca o app di origine") var bank: String?
    @Parameter(title: "Nome del conto di destinazione") var destination: String?
    // Optional source event ID for automations that can supply a stable identifier.
    @Parameter(title: "Identificativo dell’evento (facoltativo)") var eventID: String?
    static var parameterSummary: some ParameterSummary {
        Summary("Acquisisci notifica bancaria") {
            \.$notificationTitle; \.$subtitle; \.$text; \.$notificationDate
            \.$bank; \.$destination; \.$eventID
        }
    }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<CaptureTransactionEntity> {
        let capture = try makeCapture()
        do {
            let isNew = try CaptureStore.enqueue(capture)
            await CaptureImportNotifications.shared.notify(captureID: capture.id, isNew: isNew)
        } catch CaptureStore.Failure.reusedID { throw CaptureIntentFailure.reusedID }
        catch {
            throw CaptureIntentFailure.storageUnavailable
        }
        return .result(value: CaptureTransactionEntity(capture: capture), dialog: "Notifica acquisita. Controllala in Da approvare oppure passa il risultato a Prepara una spesa o Prepara un’entrata.")
    }

    @MainActor func makeCapture() throws -> PendingCapture {
        let trimmed = [notificationTitle, subtitle, text]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !trimmed.isEmpty, trimmed.count <= 30_000 else { throw CaptureIntentFailure.invalidText }
        let id: UUID
        if let eventID, !eventID.isEmpty {
            guard let supplied = UUID(uuidString: eventID) else { throw CaptureIntentFailure.invalidID }
            id = supplied
        } else { id = UUID() }
        return PendingCapture(id: id, source: "notification", sourceName: String((bank ?? "Notifica bancaria").prefix(160)), text: trimmed, destinationName: String((destination ?? "").prefix(160)), notificationDate: notificationDate)
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
