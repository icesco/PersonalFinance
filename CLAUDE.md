# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive Personal Finance iOS application built with SwiftUI and SwiftData, targeting iOS 18.0+. The app follows a hierarchical structure: **Account → Conti → Transactions** with support for categories, budgets, and transfers between accounts.

## Architecture

### Modular Design
The project uses a **local Swift Package** (`FinanceCore`) to separate data models from the main app, providing:
- Clean separation of concerns
- Reusable data layer
- Independent testing of business logic
- Easier maintenance and testing

### Data Hierarchy
```
Account (Top Level)
├── Multiple Conti (Bank accounts, credit cards, etc.)
│   └── Transactions (Income, expenses, transfers)
├── Categories (Income/Expense classification)
└── Budgets (Spending limits per category)
```

### Core Models (FinanceCore Package)
- **Account**: Main container with currency, total balance calculation
- **Conto**: Individual accounts (checking, savings, credit, investment, cash)
- **Transaction**: Financial operations with support for transfers and recurring transactions
- **RecurrenceFrequency**: Enum for transaction recurrence (daily, weekly, monthly, etc.)
- **Category**: Income/expense classification with default categories
- **Budget**: Spending limits with period tracking and alerts, supports multiple categories
- **BudgetCategory**: Junction model for Budget-Category many-to-many relationship
- **TransferLink**: Manages relationships between transfer transactions

### Terminology Mapping (Data Model vs UI)

**IMPORTANT**: The data model uses different names than what users see in the UI. This mapping is critical:

| Data Model | UI Terminology (Italian) | Description |
|------------|-------------------------|-------------|
| `Account`  | **Libro Contabile** | Top-level container grouping related financial accounts |
| `Conto`    | **Account** | Individual financial account (bank, credit card, cash, etc.) |
| `Transaction` | **Transazione** | Single financial operation |

**Hierarchy Example**:
```
Libro "Famiglia" (data: Account)
├── Account "Conto Bancario" (data: Conto)
│   └── Transazione "Spesa Supermercato" (data: Transaction)
├── Account "Carta di Credito" (data: Conto)
└── Account "Contanti" (data: Conto)

Libro "Personale" (data: Account)
├── Account "Conto Personale" (data: Conto)
└── Account "Risparmi" (data: Conto)
```

### State Management (AppStateManager)

The `AppStateManager` handles two-level hierarchical selection:

**Libro (Account) Selection**:
- `selectedAccount: Account?` - Currently selected Libro
- `showAllAccounts: Bool` - When true, aggregates data across all Libri

**Account (Conto) Selection**:
- `selectedConto: Conto?` - Currently selected Account within a Libro
- `showAllConti: Bool` - When true, shows all Accounts within selected Libro

**Selection Methods**:
```swift
// Libro selection
selectAccount(_ account: Account)  // Select specific Libro
selectAllAccounts()                // Show all Libri aggregated

// Account selection
selectConto(_ conto: Conto)        // Select specific Account
selectAllConti()                   // Show all Accounts in current Libro
```

**UI Implementation** (CryptoDashboardView):
Uses a two-level Menu picker:
1. First level: Choose Libro (or "Tutti i libri")
2. Second level: Within selected Libro, choose Account (or "Tutti gli account")

## Development Commands

### Building and Running
- **Build**: Use Xcode's build system (`Cmd+B`) or `xcodebuild -project "Personal Finance.xcodeproj" -scheme "Personal Finance" build`
- **Run**: Use Xcode to run on simulator/device (`Cmd+R`)
- **Clean**: `xcodebuild clean` or Xcode's Product > Clean Build Folder

### Testing
- **Package Tests**: `cd Packages/FinanceCore && swift test`
- **App Tests**: Run via Xcode Test Navigator or `xcodebuild test -project "Personal Finance.xcodeproj" -scheme "Personal Finance" -destination 'platform=iOS Simulator,name=iPhone 15'`
- **Test Framework**: Uses Apple's new Swift Testing framework

## Project Structure

```
Personal Finance/
├── Personal_FinanceApp.swift           # App entry point, FinanceCore integration
├── ContentView.swift                   # Main navigation with account selection
├── Views/
│   ├── AccountDetailView.swift         # Account overview and conti list
│   ├── ContoDetailView.swift          # Individual account transactions
│   ├── CreateAccountView.swift        # New account creation
│   ├── CreateContoView.swift          # New account creation
│   ├── CreateTransactionView.swift    # Transaction creation
│   └── CreateTransferView.swift       # Transfer between accounts
├── Assets.xcassets/                   # App icons and assets
├── Info.plist                         # App configuration
└── Personal_Finance.entitlements      # App capabilities

Packages/FinanceCore/                   # Local Swift Package
├── Package.swift                      # Package configuration
├── Sources/FinanceCore/
│   ├── Models/                        # All data models
│   │   ├── Account.swift
│   │   ├── Conto.swift
│   │   ├── Transaction.swift
│   │   ├── Category.swift
│   │   ├── Budget.swift
│   │   └── BudgetCategory.swift
│   └── FinanceCore.swift              # Package utilities and extensions
└── Tests/FinanceCoreTests/            # Package unit tests
```

## Key Features Implemented

### Financial Management
- **Multi-Account Support**: Create and manage multiple financial accounts
- **Account Types**: Checking, savings, credit cards, investments, cash
- **Transaction Management**: Income, expenses with category assignment
- **Recurring Transactions**: Support for daily, weekly, monthly, quarterly, and yearly recurrences
- **Transfer System**: Move money between accounts with proper linking
- **Balance Calculation**: Real-time balance updates across all accounts
- **Advanced Budgeting**: Budgets can include multiple categories with spending tracking

### User Experience
- **Three-Pane Navigation**: Account list → Account detail → Transaction detail
- **Automatic Setup**: Default account and categories created on first launch
- **Visual Feedback**: Color-coded transactions, balance indicators
- **Form Validation**: Proper input validation and error prevention

### Data Architecture Features
- **SwiftData Integration**: Modern Core Data replacement with @Model macro
- **Relationship Management**: Proper foreign key relationships between models
- **Schema Evolution**: Prepared for future migrations
- **Default Data**: Pre-configured categories for immediate use

## Development Patterns

### SwiftUI Conventions
- **NavigationSplitView**: Three-pane layout optimized for iPad
- **@Query**: Real-time data binding with SwiftData
- **Environment Values**: ModelContext injection throughout view hierarchy
- **Sheet Presentations**: Modal forms for creation workflows
- **ContentUnavailableView**: Proper empty state handling

### Data Management
- **Repository Pattern**: FinanceCore package acts as data repository
- **Relationship Integrity**: Cascade deletes and proper relationship setup
- **Transfer Logic**: Dual-transaction system for proper money movement tracking
- **Currency Formatting**: Localized currency display with Decimal precision

### Code Organization
- **Separation of Concerns**: UI in main app, business logic in package
- **Preview Support**: Comprehensive SwiftUI previews with mock data
- **Type Safety**: Strong typing with enums for account types, transaction types
- **Extension Pattern**: Utility extensions in FinanceCore for common operations

## Next Steps for Development

1. **Category Management**: Add ability to create/edit/delete categories
2. **Budget Implementation**: Complete budget tracking and alerts system
3. **Reports & Analytics**: Add spending analysis and financial reports
4. **Data Export**: CSV/PDF export functionality
5. **Settings**: App preferences and account management
6. **Search & Filtering**: Transaction search and filtering capabilities

## Bundle Configuration
- Bundle ID: `cc.fbianco.finance.Personal-Finance`
- Deployment target: iOS 18.0
- Category: Finance app
- Universal app (iPhone + iPad)
- Remote notification support enabled