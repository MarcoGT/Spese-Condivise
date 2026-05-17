# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a pure Xcode project — there is no `Package.swift`, no SPM dependencies, and no external tooling.

```bash
# Build from CLI (simulator)
xcodebuild -project "Spese Condivise.xcodeproj" \
           -scheme "Spese Condivise" \
           -destination "platform=iOS Simulator,name=iPhone 16" \
           build

# Run tests
xcodebuild -project "Spese Condivise.xcodeproj" \
           -scheme "Spese Condivise" \
           -destination "platform=iOS Simulator,name=iPhone 16" \
           test
```

CloudKit features (sharing, sync) require a real device with an iCloud account — they do not work in the simulator.

## Architecture Overview

**Spese Condivise** is an iOS SwiftUI app for splitting shared expenses. Each "sheet" (`SharedSheet`) is a ledger shared between people; expenses track who paid and who splits the cost.

### Persistence — two Core Data stores

`PersistenceController` (singleton) manages an `NSPersistentCloudKitContainer` with **two stores**:

| Store | Config name | CloudKit DB scope |
|---|---|---|
| `SharedExpenses.sqlite` | `Private` | `.private` |
| `shared.sqlite` | `CloudSharing` | `.shared` |

`sharedPersistentStore` (the `CloudSharing` store) is where accepted share invitations are written. Always use `executeWhenReady(_:)` before calling `acceptShareInvitations`, because both stores load asynchronously and `sharedPersistentStore` is nil until the CloudSharing store finishes loading.

### Data model (`SharedExpenses.xcdatamodeld`)

```
SharedSheet  ──< Expense >── Person   (paidBy)
             ──< Person            (persons)
Expense      ──< Person            (splitBetween)
```

- `SharedSheet`: `id`, `name`, `currencyCode`, `lastUpdated`, `→persons`, `→expenses`
- `Expense`: `id`, `amount`, `note`, `date`, `archived`, `→paidBy` (Person), `→splitBetween` (Set<Person>), `→sheet`
- `Person`: `id`, `name`, `→sheet`

Convenience sorted arrays: `sheet.expensesArray` (date desc), `sheet.personsArray` (name asc).

### Balance calculation

`SharedSheet+Balances.swift` is the source of truth:
- Payer is credited the full expense amount.
- Every person in `splitBetween` is debited `amount / splitBetween.count`.
- `balance(for: UUID)` returns a single person's net (positive = owed money, negative = owes money).

The same logic is duplicated in `SheetDetailView` and `SharedSheetListView` — prefer the extension methods when refactoring.

### "Current user" identity

`CurrentUser` (environment object) holds the UUID of the local user's `Person` record. It is **bootstrapped once** from the first person in the first sheet (`bootstrapIfNeeded`) and never persisted — it resets on reinstall. This is a deliberate simplification, not a bug.

### CloudKit sharing flow

**Sharing (owner):**
1. `SheetDetailView.openShare()` checks for an existing `CKShare` via `fetchShares(matching:)`.
2. If none exists, calls `container.share([sheet], to: nil)` to create one.
3. Saves the share via `CKModifyRecordsOperation` — the URL is only valid in the response record from `perRecordSaveBlock`, not from the local object passed in.
4. Presents `ActivityView` (a `UIActivityViewController` wrapper) with the URL.

**Accepting (recipient):**
- Via deep link: `SharedExpensesApp.handleIncomingURL` → `handleCloudKitShare` → `acceptShareInvitations(from:into:sharedStore)`.
- Via native iOS: `AppDelegate.application(_:userDidAcceptCloudKitShareWith:)` → same `acceptShareInvitations` call.
- Both paths call `executeWhenReady` to defer until both stores are loaded.

### UI structure

```
SharedExpensesApp (App)
└── SharedSheetListView          root: list of sheets + total balance
    ├── SyncOverlay              modal loading screen on first launch (0.8 s)
    └── SheetDetailView          per-sheet expenses and per-person balances
        ├── AddExpenseView       create or edit an expense (modal sheet)
        └── ActivityView         UIActivityViewController for sharing the sheet URL
```

### Localization

All user-facing strings go through `NSLocalizedString`. The string catalog is `Localizable.xcstrings` at the repo root. The app is localised in Italian and English; Italian strings often appear hardcoded in comments or error messages — these should be extracted to the catalog when touched.
