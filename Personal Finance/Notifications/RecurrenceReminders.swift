import SwiftUI
import SwiftData
import UserNotifications
import FinanceCore

/// Notifications join the same deferred navigation path as shortcuts and widgets.
/// Only the user's tap opens planning; dismissing a notification has no effect.
@MainActor
final class ReminderNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderNotificationRouter()

    func install() { UNUserNotificationCenter.current().delegate = self }

    func receive(identifier: String, action: String, inbox: FinanceShortcutInbox? = nil) {
        guard identifier.hasPrefix("forgia.recurrence."), action == UNNotificationDefaultActionIdentifier else { return }
        let inbox = inbox ?? .shared
        do { try inbox.submit(.reminderPlanning) }
        catch { inbox.reportError("Completa la richiesta già aperta, poi consulta le scadenze da Pianifica.") }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        // UIKit updates its background snapshot when this callback completes.
        // The async delegate bridge can complete on a cooperative worker thread.
        Task { @MainActor in
            receive(identifier: identifier, action: action)
            completionHandler()
        }
    }
}

#if DEBUG
/// Synthetic local notification for an end-to-end system UI test; never built into Release.
struct ReminderNotificationFixture: View {
    @State private var status = ""
    @State private var authorized = false
    @Environment(RecurrenceReminders.self) private var reminders

    var body: some View {
        VStack {
            Button("Autorizza notifica di prova") {
                Task {
                    authorized = (try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])) == true
                    if !authorized { status = "Autorizzazione negata" }
                }
            }
            Button("Programma promemoria di prova") {
                Task {
                    let center = UNUserNotificationCenter.current()
                    do {
                        // Let reconciliation after the permission dialog finish before
                        // adding this synthetic request outside the real reminder plan.
                        await reminders.waitForPendingUpdates()
                        let content = UNMutableNotificationContent()
                        content.title = "Promemoria Formi di prova"
                        content.body = "Apri le scadenze. Dati sintetici."
                        content.sound = .default
                        let request = UNNotificationRequest(identifier: "forgia.recurrence.uitest", content: content,
                                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false))
                        try await center.add(request)
                        status = "Promemoria programmato"
                    } catch { status = "Programmazione non riuscita" }
                }
            }
            .disabled(!authorized)
            Text(status)
        }.padding().background(.regularMaterial)
    }
}
#endif

@MainActor
protocol RecurrenceNotificationCenter: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers: [String])
    func deliveredNotifications() async -> [UNNotification]
    func removeDeliveredNotifications(withIdentifiers: [String])
    func isAuthorized() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
final class SystemRecurrenceNotificationCenter: RecurrenceNotificationCenter {
    private let center = UNUserNotificationCenter.current()
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { try await center.requestAuthorization(options: options) }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func deliveredNotifications() async -> [UNNotification] { await center.deliveredNotifications() }
    func removeDeliveredNotifications(withIdentifiers ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
}

@MainActor
@Observable
final class RecurrenceReminders {
    private(set) var enabled: Bool
    var hour: Int { didSet { defaults.set(hour, forKey: "reminders.hour") } }
    var minute: Int { didSet { defaults.set(minute, forKey: "reminders.minute") } }
    var daysBefore: Int { didSet { defaults.set(daysBefore, forKey: "reminders.daysBefore") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, center: (any RecurrenceNotificationCenter)? = nil,
         now: @escaping @MainActor () -> Date = { Date() }) {
        self.defaults = defaults
        self.center = center ?? SystemRecurrenceNotificationCenter()
        self.currentDate = now
        enabled = defaults.bool(forKey: "reminders.enabled")
        hour = defaults.object(forKey: "reminders.hour") as? Int ?? 9
        minute = defaults.integer(forKey: "reminders.minute")
        daysBefore = defaults.integer(forKey: "reminders.daysBefore")
    }

    private(set) var status: String?
    private(set) var requestingPermission = false
    private var desired: [DailyRecurrenceReminder] = []
    private var revision = 0
    private var worker: Task<Void, Never>?
    private let center: any RecurrenceNotificationCenter
    private let currentDate: @MainActor () -> Date

    func waitForPendingUpdates() async { await worker?.value }

    func setEnabled(_ value: Bool) async {
        guard !requestingPermission else { return }
        if value {
            requestingPermission = true
            defer { requestingPermission = false }
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    status = "Notifiche non autorizzate. Puoi abilitarle nelle impostazioni del dispositivo."
                    return
                }
            } catch { status = "Impossibile richiedere le notifiche: \(error.localizedDescription)"; return }
        }
        enabled = value
        defaults.set(value, forKey: "reminders.enabled")
        status = nil
        update(desired)
    }

    func update(_ plans: [DailyRecurrenceReminder]) {
        #if DEBUG
        // Keep the demo session from changing system reminders, while allowing
        // injected notification centers to exercise reconciliation in tests.
        if ProcessInfo.processInfo.arguments.contains("UITEST_MAC_LOCAL"),
           center is SystemRecurrenceNotificationCenter { return }
        #endif
        desired = plans
        revision += 1
        guard worker == nil else { return }
        worker = Task { await reconcile() }
    }

    private func reconcile() async {
        defer { worker = nil }
        while true {
            let version = revision
            let plans = enabled ? Array(desired.prefix(60)) : []
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("forgia.recurrence.") }.map(\.identifier))
            if !enabled {
                let delivered = await center.deliveredNotifications()
                center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("forgia.recurrence.") }.map { $0.request.identifier })
            }
            if revision != version { continue }
            if enabled {
                let authorized = await center.isAuthorized()
                guard revision == version else { continue }
                guard authorized else {
                    status = "Notifiche disattivate nelle impostazioni del dispositivo."
                    return
                }
            }
            var failed = false
            var scheduledCount = 0
            for plan in plans {
                guard revision == version else { break }
                // Permission and notification-center calls can outlive a planned
                // fire date. Never re-add an expired calendar trigger.
                guard plan.fireDate > currentDate() else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Scadenze da controllare"
                content.body = "Hai \(plan.count) scadenze da controllare in Formi."
                content.sound = .default
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
                components.timeZone = .current
                let request = UNNotificationRequest(identifier: plan.identifier, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                do { try await center.add(request); scheduledCount += 1 }
                catch { status = "Alcuni promemoria non sono stati programmati. Riapri l'app per riprovare."; failed = true }
            }
            if version == revision {
                if !failed { status = enabled ? "\(scheduledCount) promemoria programmati su questo dispositivo." : nil }
                return
            }
        }
    }
}

/// Observes model changes, including CloudKit imports, rather than depending on individual save buttons.
struct RecurrenceReminderObserver: View {
    @Environment(RecurrenceReminders.self) private var reminders
    @Environment(\.scenePhase) private var phase
    @Query(filter: #Predicate<FinanceTransaction> { $0.isRecurring == true }) private var sources: [FinanceTransaction]
    @Query private var scheduled: [FinanceTransaction]
    @Query private var resolutions: [RecurrenceResolution]
    @State private var now = Date()

    init() {
        let cutoff = Calendar.current.startOfDay(for: Date())
        _scheduled = Query(filter: #Predicate<FinanceTransaction> {
            $0.date > cutoff && $0.recurrenceSourceID == nil
        })
    }

    private var plans: [DailyRecurrenceReminder] {
        guard reminders.enabled else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 31, to: start) ?? now
        let resolved = Set(resolutions.map(\.key))
        var dates = sources.flatMap { source -> [Date] in
            let conto = source.type == .income ? source.toConto : source.fromConto
            guard conto?.isActive == true, conto?.account?.isActive == true else { return [] }
            return source.recurrenceDates(after: max(source.date, start.addingTimeInterval(-1)), through: end)
                .filter { !resolved.contains(RecurrenceResolution.key(sourceID: source.id, date: $0)) }
        }
        dates += ScheduledTransactionReminders.dates(transactions: scheduled, now: now, through: end)
        return RecurringReminderPlanner.plan(occurrences: dates, hour: reminders.hour, minute: reminders.minute,
                                              daysBefore: reminders.daysBefore, now: now)
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: phase == .active && reminders.enabled) {
                guard phase == .active, reminders.enabled,
                      ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
                // Refresh the rolling horizon and local calendar while a window
                // stays open. SwiftUI cancels this when inactive or disabled.
                while !Task.isCancelled {
                    now = Date()
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
                }
            }
            .onChange(of: plans, initial: true) { _, value in
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
                reminders.update(value)
            }
            .onChange(of: phase) { _, value in
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
                if value == .active { now = Date(); reminders.update(plans) }
            }
    }
}

struct RecurrenceReminderSettings: View {
    @Environment(RecurrenceReminders.self) private var reminders
    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: reminders.hour, minute: reminders.minute, second: 0, of: Date()) ?? Date()
        }, set: {
            reminders.hour = Calendar.current.component(.hour, from: $0)
            reminders.minute = Calendar.current.component(.minute, from: $0)
        })
    }
    var body: some View {
        @Bindable var reminders = reminders
        Section {
            Toggle("Promemoria delle scadenze", isOn: Binding(get: { reminders.enabled }, set: { value in
                Task { await reminders.setEnabled(value) }
            })).disabled(reminders.requestingPermission)
            if reminders.enabled {
                DatePicker("Orario", selection: time, displayedComponents: .hourAndMinute)
                Picker("Avvisa", selection: $reminders.daysBefore) {
                    Text("Il giorno stesso").tag(0)
                    Text("Il giorno prima").tag(1)
                }
            }
            if let status = reminders.status { Text(status).font(.caption).foregroundStyle(.secondary) }
        } header: { Text("Promemoria") } footer: {
            Text("Un riepilogo al giorno, senza importi o nomi nelle notifiche. Include ricorrenze e movimenti futuri inseriti da te per circa 30 giorni e si aggiorna quando apri o modifichi l'app. La preferenza vale solo su questo dispositivo.")
        }
    }
}
