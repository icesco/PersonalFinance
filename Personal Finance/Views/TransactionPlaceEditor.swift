import SwiftUI
import CoreLocation
import FinanceCore

struct PlaceDraft {
    var name = ""
    var latitude: Double?
    var longitude: Double?
    var accuracy: Double?

    init() { }
    init(transaction: FinanceTransaction) {
        name = transaction.placeName ?? ""
        latitude = transaction.latitude
        longitude = transaction.longitude
        accuracy = transaction.locationAccuracy
    }
    func apply(to transaction: FinanceTransaction) {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.placeName = label.isEmpty ? nil : label
        transaction.latitude = latitude
        transaction.longitude = longitude
        transaction.locationAccuracy = accuracy
    }
}

@MainActor
@Observable
final class SingleLocationRequest: NSObject, @preconcurrency CLLocationManagerDelegate {
    struct Fix: Equatable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
    }
    private(set) var fix: Fix?
    private(set) var isRequesting = false
    private(set) var error: String?
    private let manager = CLLocationManager()
    private var timeout: Task<Void, Never>?

    // Core Location delivers delegate calls on the run loop where this main-actor manager was created.
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func request() {
        guard !isRequesting else { return }
        error = nil
        fix = nil
        isRequesting = true
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            self?.fail("Posizione non disponibile. Riprova oppure indica il luogo a mano.")
        }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: fail("Accesso alla posizione non consentito. Puoi indicare il luogo a mano.")
        }
    }
    func cancel() {
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        isRequesting = false
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRequesting else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: fail("Accesso alla posizione non consentito. Puoi indicare il luogo a mano.")
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRequesting else { return }
        guard let location = locations.last, location.horizontalAccuracy >= 0, location.horizontalAccuracy.isFinite,
              abs(location.timestamp.timeIntervalSinceNow) < 60,
              CLLocationCoordinate2DIsValid(location.coordinate) else {
            fail("La posizione ricevuta non è aggiornata. Riprova."); return
        }
        fix = Fix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy)
        cancel()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isRequesting else { return }
        fail("Impossibile rilevare la posizione. Puoi indicare il luogo a mano.")
    }
    private func fail(_ message: String) { error = message; cancel() }
}

struct TransactionPlaceEditor: View {
    @Binding var place: PlaceDraft
    @Binding var isLocating: Bool
    /// Card rows matching the quick-entry and edit forms; off inside system `Form`s.
    var cardStyle = false
    @State private var request = SingleLocationRequest()

    private var coordinates: String? {
        guard let latitude = place.latitude, let longitude = place.longitude else { return nil }
        return "\(latitude.formatted(.number.precision(.fractionLength(4)))), \(longitude.formatted(.number.precision(.fractionLength(4))))"
    }

    private let privacyNote = "La posizione viene rilevata solo su richiesta e salvata con il movimento. Non viene tracciata in background."

    var body: some View {
        Group {
            if cardStyle { card } else { classic }
        }
        .onChange(of: request.isRequesting, initial: true) { _, value in isLocating = value }
        .onChange(of: request.fix) { _, fix in
            guard let fix else { return }
            place.latitude = fix.latitude; place.longitude = fix.longitude; place.accuracy = fix.accuracy
        }
        .onDisappear { request.cancel() }
    }

    private func clearCoordinates() {
        request.cancel()
        place.latitude = nil; place.longitude = nil; place.accuracy = nil
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormCard(title: "Luogo") {
                FormRow(icon: "mappin.and.ellipse", tint: ForgiaPalette.apricotSurface) {
                    TextField("Nome del luogo (opzionale)", text: $place.name)
                }
                FormRowDivider()
                if let coordinates {
                    FormRow(icon: "location.fill", tint: ForgiaPalette.sageSurface) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coordinates).font(.subheadline).monospacedDigit()
                            if let accuracy = place.accuracy {
                                Text("Precisione stimata: \(accuracy.formatted(.number.precision(.fractionLength(0)))) m")
                                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                            }
                        }
                        Spacer(minLength: 8)
                        Button("Rimuovi", role: .destructive, action: clearCoordinates)
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                    }
                    FormRowDivider()
                }
                FormRow(icon: "location") {
                    Button(coordinates == nil ? "Usa posizione attuale" : "Aggiorna posizione") { request.request() }
                        .buttonStyle(.borderless)
                        .tint(ForgiaPalette.accent)
                        .disabled(request.isRequesting)
                    Spacer(minLength: 8)
                    if request.isRequesting { ProgressView() }
                }
                if let error = request.error {
                    Text(error)
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
            Text(privacyNote)
                .font(.caption)
                .foregroundStyle(ForgiaPalette.mutedText)
                .padding(.horizontal, 4)
        }
    }

    private var classic: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Luogo").font(.headline)
            TextField("Nome del luogo (opzionale)", text: $place.name)
                .textFieldStyle(.roundedBorder)
            if let coordinates {
                Text(coordinates).font(.caption).monospacedDigit()
                if let accuracy = place.accuracy {
                    Text("Precisione stimata: \(accuracy.formatted(.number.precision(.fractionLength(0)))) m").font(.caption).foregroundStyle(.secondary)
                }
                Button("Rimuovi coordinate", role: .destructive, action: clearCoordinates)
            }
            Button("Usa posizione attuale", systemImage: "location") { request.request() }
                .buttonStyle(.bordered).disabled(request.isRequesting)
            if request.isRequesting { ProgressView("Rilevamento posizione…") }
            if let error = request.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            Text(privacyNote)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
