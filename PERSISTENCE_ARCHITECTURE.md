# Personal Finance - Persistence Architecture

## Overview

The Personal Finance app implements a sophisticated persistence architecture based on Planoma's proven patterns, providing:

- **Dynamic Container Creation**: Containers are created dynamically with CloudKit and App Group support
- **Thread-Safe Management**: All container operations are thread-safe using dedicated queues
- **Widget Compatibility**: Shared data access across main app and widgets
- **Cloud Sync Toggle**: Users can enable/disable iCloud sync at runtime
- **Data Migration**: Automatic migration from legacy local storage to App Group

## Key Components

### 1. FinanceCoreModule

**File**: `Packages/FinanceCore/Sources/FinanceCore/FinanceCore.swift`

Enhanced SwiftData container factory with:

```swift
// Dynamic container creation with CloudKit support
FinanceCoreModule.createModelContainer(
    appGroupIdentifier: "group.personalfinance.shared",
    enableCloudKit: true,
    inMemory: false
)

// Widget-specific container (always local)
FinanceCoreModule.widgetModelContainer(
    appGroupIdentifier: "group.personalfinance.shared"
)
```

**Key Features**:
- Thread-safe container management using `DispatchQueue`
- CloudKit integration with container identifier: `iCloud.cc.francescobianco.personalfinance`
- App Group support with identifier: `group.personalfinance.shared`
- Automatic fallback to local storage if App Group unavailable

### 2. DataStorageManager

**File**: `Packages/FinanceCore/Sources/FinanceCore/FinanceCore.swift` (integrated)

@Observable class managing:
- Cloud sync preferences (stored in App Group UserDefaults)
- Container switching between local/cloud storage
- Data migration from legacy locations
- CloudKit account status monitoring

**Usage**:
```swift
let manager = DataStorageManager.shared

// Toggle cloud sync
manager.isCloudSyncEnabled = true

// Check CloudKit availability
let isAvailable = await manager.isCloudKitAvailable()

// Initialize container
try await manager.initializeContainer()
```

### 3. WidgetDataProvider

**File**: `Packages/FinanceCore/Sources/FinanceCore/WidgetDataProvider.swift`

Cross-process data provider for widgets:
- Lightweight data models (`AccountSummary`, `TransactionSummary`)
- Widget-optimized data fetching
- Shared container access using App Group

**Usage**:
```swift
let provider = WidgetDataProvider.shared

// Fetch data for widget
let accounts = try provider.fetchAccountSummaries()
let recentTransactions = try provider.fetchRecentTransactions(limit: 5)
let totalBalance = try provider.fetchTotalBalance()
```

## App Configuration

### Entitlements

**File**: `Personal Finance/Personal_Finance.entitlements`

Required entitlements:
- CloudKit services
- iCloud container: `iCloud.cc.francescobianco.personalfinance`
- App Groups: `group.personalfinance.shared`

### App Initialization

**File**: `Personal Finance/Personal_FinanceApp.swift`

The main app now:
1. Initializes `DataStorageManager`
2. Performs automatic data migration
3. Creates appropriate container based on sync preferences
4. Provides loading/error states during initialization

## Settings Integration

### SettingsView

**File**: `Personal Finance/Views/SettingsView.swift`

User interface for:
- Toggling CloudKit sync on/off
- Viewing CloudKit account status
- Storage location information
- App Group configuration details

### Navigation Integration

Settings are integrated into the main navigation flow via `NavigationRouter`.

## Data Migration

### Automatic Migration

The system automatically detects and migrates data from:
- **From**: App's Documents directory (`PersonalFinance.sqlite`)
- **To**: App Group container (`group.personalfinance.shared/PersonalFinance.sqlite`)

Migration includes:
- Main database file
- WAL (Write-Ahead Logging) files
- SHM (Shared Memory) files

### Migration Process

1. Check if old database exists in Documents directory
2. Check if new database exists in App Group container
3. If migration needed, create App Group directory
4. Copy all database files to new location
5. Continue with normal app initialization

## Widget Architecture

### Shared Data Access

Widgets access the same data through:
- App Group shared container
- `WidgetDataProvider` for optimized queries
- Local-only storage (no CloudKit in widgets)

### Data Models

Lightweight models for widget display:
- `AccountSummary`: Basic account information
- `TransactionSummary`: Recent transaction data
- `WidgetConfiguration`: Widget settings

## Thread Safety

### Container Queue

All container operations use a dedicated serial queue:
```swift
private static let containerQueue = DispatchQueue(
    label: "com.personalfinance.container", 
    qos: .userInitiated
)
```

### Thread-Safe Operations

- Container creation
- Shared container management
- Preference updates

## CloudKit Integration

### Container Configuration

- **Identifier**: `iCloud.cc.francescobianco.personalfinance`
- **Database**: Private CloudKit database
- **Schema**: Automatic SwiftData schema sync

### Account Status Monitoring

The app monitors CloudKit account status:
- Available: Full sync functionality
- No Account: Local storage only
- Restricted: Local storage with warnings
- Temporarily Unavailable: Retry logic

### Dynamic Sync Toggle

Users can enable/disable CloudKit sync at runtime:
- Immediate container recreation
- Preference stored in App Group UserDefaults
- UI feedback for sync status

## Best Practices

### Container Management

1. Always use `DataStorageManager.shared` for container access
2. Check `isCloudSyncEnabled` before making sync assumptions
3. Handle container creation failures gracefully

### Widget Development

1. Use `WidgetDataProvider` for all data access
2. Keep data models lightweight
3. Implement proper error handling for cross-process access

### Error Handling

1. Container creation errors are displayed to user
2. Migration failures are logged and retried
3. CloudKit errors provide user-friendly messages

## Future Enhancements

### Widget Support

Ready for widget implementation:
- Shared container architecture in place
- Optimized data provider available
- Cross-process communication established

### Background Sync

Infrastructure supports:
- Background CloudKit sync
- Conflict resolution
- Incremental updates

### Multi-Device Sync

CloudKit integration enables:
- Automatic cross-device synchronization
- Conflict resolution
- Offline-first architecture

## Migration Path

### From Legacy Architecture

1. App detects legacy database
2. Automatically migrates to App Group
3. Continues with new architecture
4. Legacy database remains untouched (backup)

### To Widget Integration

1. Create widget extension target
2. Add App Group entitlement to widget
3. Use `WidgetDataProvider` for data access
4. Implement widget timeline provider

This architecture provides a solid foundation for the Personal Finance app with modern persistence patterns, cross-device sync, and widget support.

## Derived ledger cache

`Conto.ledgerCacheJSON` is an optional, rebuildable projection in the existing SwiftData/CloudKit model. `LedgerCache` computes recorded balances, timestamp histories, and monthly income, expenses, transfer changes and expense categories. Home, widget and Watch readers validate and consume this common projection from their own background contexts. Forecasts and savings interest valuations continue to use current source data.

Cache validation compares a versioned SHA-256 fingerprint of the actual recorded movement values and initial balance. It covers amount/date/type/category/endpoint edits, deletions and transfers, including destination amounts. Future movements enter the fingerprint when their date matures. A synced cache that arrives before its movements is rejected. No timestamp or row count alone establishes freshness; no mutation entry point needs a separate invalidation marker. Version 2 includes a checksummed `calculatedAt` date, preserved on reuse (including time-zone changes) and advanced only when rebuilding the recorded history. A newer date never overrides a mismatching fingerprint; device-clock differences cannot authorize stale calculations. Older payloads without this field are rebuilt automatically.

Only cache misses produce persistence updates. Writers save in fresh cache-only contexts and treat cache-save failures as nonfatal. Payloads have an integrity checksum and a 512 KiB persistence limit. Version 3 keeps transaction-level history up to 128 KiB; larger payloads store daily closing balances, and fall back to monthly closing balances if needed to fit the persistence limit. Extremely large summaries may still exceed the limit, in which case the computed projection remains usable without persisting it. Cache point identities are deterministic. Different calendars/time zones derive local groups from source movements without overwriting a valid remote cache merely for a calendar difference.

Charts use transaction detail for windows up to 31 days, daily closing values up to 732 days, and monthly closing values for longer windows. They preserve exact opening/closing boundaries (including intraday cuts and exclusive period ends) using source movements when the stored history is compact. A short window or finer requested resolution reconstructs detail from those movements; compacted values are actual closing balances, never averages. Quiet days/months do not add redundant stored points. Source fingerprints, totals, monthly summaries and calculation dates retain the same validation guarantees across all stored resolutions.

Validation still reads the source movements; this change avoids repeated history/aggregate calculations, rather than eliminating every store fetch. Widget history periods share a single validated projection per snapshot. Algorithm changes must increment `LedgerCache.version`.

Interactive balance charts load prepared series through `BalanceSeriesReader`, using a fresh context owned by a background actor and the same validated ledger history. The views retain those value snapshots between refreshes, so gesture and selection updates do not fetch movements or rebuild financial series inside `body`. Scope changes, saves, remote changes and foreground refreshes trigger a debounced reload; forecasts are derived alongside the cached recorded history.

`LedgerCalculationCoordinator` serializes the shared ledger preparation for Home, chart, widget and Watch readers. It memoizes per container/account/calendar using exact equality of the recorded source values and opening balance; equal row counts or dates alone cannot reuse work. Payload changes still require validation or repair. Requests from different consumers or overlapping scopes share results, and future movement maturity changes the eligible source set. The in-memory cache retains at most 32 account/calendar entries and 50,000 source values. Each reader continues to own its context and fetches the source records needed for its other calculations; this coordinator does not eliminate every query.

`FinanceDataChangeCenter` captures immutable scopes on the saving context's executor before saving, then publishes them only after a successful save. Transaction edits include remembered old and current endpoints, so moving or deleting a transfer refreshes both affected accounts. Inverse relationship changes on otherwise unchanged accounts/categories do not trigger a global refresh. Missing original scope, configuration changes and unidentified remote changes conservatively refresh all relevant consumers. Home's refresh scope also includes archived accounts used by its budgets. Explicitly marked fresh cache-only contexts save silently, preventing derived-cache refresh loops. Replaced containers cannot notify consumers attached to another container.

The app groups mirroring waves through `CloudSyncSession`: 2 seconds of quiescence end a session, and the progress banner is announced only after 3 seconds. Fast successful sessions refresh data quietly. Failures survive gaps and overlapping events; duplicate/unknown events cannot end another operation. An active event that falls silent for 20 seconds releases the banner without claiming sync success. Container replacement or disabling iCloud cancels pending session timers. The policy is covered with simulated clocks; actual CloudKit delivery and device frame times remain separate verification.

The optional field supports additive local-store evolution. Distribution using the production CloudKit environment requires the new `Conto` field to exist in that environment. Local tests/builds do not prove production schema deployment or actual cross-device delivery. The explicit shared-book transport continues to transfer source records; its separate protocol does not transmit these derived cache payloads.
