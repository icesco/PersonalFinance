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
    @State private var request = SingleLocationRequest()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Luogo").font(.headline)
            TextField("Nome del luogo (opzionale)", text: $place.name)
                .textFieldStyle(.roundedBorder)
            if let latitude = place.latitude, let longitude = place.longitude {
                Text("\(latitude.formatted(.number.precision(.fractionLength(4)))), \(longitude.formatted(.number.precision(.fractionLength(4))))")
                    .font(.caption).monospacedDigit()
                if let accuracy = place.accuracy {
                    Text("Precisione stimata: \(accuracy.formatted(.number.precision(.fractionLength(0)))) m").font(.caption).foregroundStyle(.secondary)
                }
                Button("Rimuovi coordinate", role: .destructive) {
                    request.cancel()
                    place.latitude = nil; place.longitude = nil; place.accuracy = nil
                }
            }
            Button("Usa posizione attuale", systemImage: "location") { request.request() }
                .buttonStyle(.bordered).disabled(request.isRequesting)
            if request.isRequesting { ProgressView("Rilevamento posizione…") }
            if let error = request.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            Text("La posizione viene rilevata solo su richiesta e salvata con il movimento. Non viene tracciata in background.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: request.isRequesting, initial: true) { _, value in isLocating = value }
        .onChange(of: request.fix) { _, fix in
            guard let fix else { return }
            place.latitude = fix.latitude; place.longitude = fix.longitude; place.accuracy = fix.accuracy
        }
        .onDisappear { request.cancel() }
    }
}
