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