import SwiftUI
import CoreData
import CloudKit
import UIKit

struct SheetDetailView: View {

    @ObservedObject var sheet: SharedSheet
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var currentUser: CurrentUser

    @FetchRequest private var expenses: FetchedResults<Expense>

    @State private var activeModal: ActiveModal?
    @State private var showAddPersonAlert = false
    @State private var newPersonName = ""
    @State private var showingShareError = false
    @State private var shareErrorMessage = ""
    @State private var isPreparingShare = false
    @State private var showSettleConfirm = false
    @State private var showStatistics = false
    @State private var searchText = ""
    @State private var selectedCategoryFilter: ExpenseCategory? = nil
    @State private var personToClaimAsMe: Person? = nil
    @State private var isExportingPDF = false
    @State private var showExchangeRateEditor = false

    enum ActiveModal: Identifiable {
        case add
        case edit(Expense)
        case share(URL)

        var id: String {
            switch self {
                case .add: return "add"
                case .edit(let expense): return "edit-\(expense.objectID.uriRepresentation().absoluteString)"
                case .share(let url): return "share-\(url.absoluteString)"
            }
        }
    }

    init(sheet: SharedSheet) {
        self.sheet = sheet

        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Expense.date, ascending: false)
        ]
        // archived != YES gestisce correttamente anche valori NULL (es. dopo sync CloudKit)
        request.predicate = NSPredicate(format: "sheet == %@ AND archived != YES", sheet)

        _expenses = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            List {
                // MARK: Persons section
                if let persons = sheet.persons as? Set<Person>, !persons.isEmpty {
                    Section {
                        let balances = balancesPerPerson(sheet: sheet)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(sheet.personsArray) { person in
                                    let value = balances[person] ?? 0
                                    let isMe = person.objectID == myPerson?.objectID
                                    let claimMode = isSharedSheet && !isIdentifiedInSheet
                                    PersonBalanceCard(
                                        person: person,
                                        value: value,
                                        isMe: isMe,
                                        balanceColor: balanceColor(value),
                                        balanceText: personBalanceText(value, isMe: isMe),
                                        onTap: claimMode ? { personToClaimAsMe = person } : nil
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())

                        // Banner "chi sei tu?" visibile solo nei fogli condivisi
                        // dove l'utente non si è ancora identificato
                        if isSharedSheet && !isIdentifiedInSheet {
                            HStack(spacing: 10) {
                                Image(systemName: "person.fill.questionmark")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("identify_prompt_title", comment: ""))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(NSLocalizedString("identify_prompt_body", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .listRowBackground(Color.accentColor.opacity(0.06))
                        }
                    } header: {
                        SectionHeader(title: NSLocalizedString("Persone", comment: "people"))
                    }
                }

                // MARK: Settle-up section (chi paga chi)
                if !expenses.isEmpty {
                    let transfers = sheet.suggestedTransfers()
                    let sheetCurrency = sheet.currencyCode ?? "EUR"
                    let reimbCurrency = sheet.reimbursementCurrencyCode
                    let rate = sheet.exchangeRate
                    let hasConversion = reimbCurrency != nil && rate > 0 && reimbCurrency != sheetCurrency
                    let currSym = currencySymbol(code: sheetCurrency)
                    let reimbSym = reimbCurrency.map { currencySymbol(code: $0) } ?? currSym

                    Section {
                        if transfers.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(NSLocalizedString("settle_all_even", comment: ""))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        } else {
                            ForEach(transfers) { t in
                                HStack(spacing: 8) {
                                    Text(t.from.name ?? "—")
                                        .fontWeight(.medium)
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(t.to.name ?? "—")
                                        .fontWeight(.medium)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(AmountFormatter.format(t.amount, currencySymbol: currSym))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.accentColor)
                                        if hasConversion {
                                            Text("≈ " + AmountFormatter.format(t.amount * rate, currencySymbol: reimbSym))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }

                            Button {
                                showExchangeRateEditor = true
                            } label: {
                                HStack {
                                    Image(systemName: hasConversion ? "arrow.2.circlepath" : "plusminus.circle")
                                        .foregroundColor(.secondary)
                                    Text(hasConversion
                                         ? String(format: NSLocalizedString("exchange_rate_edit", comment: ""), sheetCurrency, reimbCurrency ?? "", rate)
                                         : NSLocalizedString("exchange_rate_set", comment: ""))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    } header: {
                        SectionHeader(title: NSLocalizedString("settle_who_pays_whom", comment: ""))
                    }
                }

                // MARK: Category filter chips
                if !expenses.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // "Tutte" chip
                                Button {
                                    selectedCategoryFilter = nil
                                } label: {
                                    Text(NSLocalizedString("all_categories", comment: ""))
                                        .font(.subheadline)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(selectedCategoryFilter == nil ? Color.accentColor : Color(.systemGray5))
                                        .foregroundColor(selectedCategoryFilter == nil ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                // Una chip per ogni categoria presente nelle spese
                                ForEach(usedCategories, id: \.self) { cat in
                                    let isSelected = selectedCategoryFilter == cat
                                    Button {
                                        selectedCategoryFilter = isSelected ? nil : cat
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: cat.icon)
                                                .font(.caption)
                                            Text(cat.localizedName)
                                                .font(.subheadline)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(isSelected ? cat.color : Color(.systemGray5))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                }

                // MARK: Expenses section
                Section {
                    if expenses.isEmpty {
                        if !sheet.settlementsArray.isEmpty {
                            // Tutte le spese sono state archiviate con un azzeramento
                            AllSettledEmptyView { activeModal = .add }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else if isSharedSheet && !isIdentifiedInSheet {
                            // Foglio condiviso appena accettato: dati ancora in arrivo
                            SharedSyncEmptyView()
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            EmptyExpensesView { activeModal = .add }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else if filteredExpenses.isEmpty {
                        // Nessun risultato per ricerca/filtro
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("no_results", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredExpenses) { expense in
                            let isNew = (expense.createdAt ?? .distantPast) > LastSeenStore.lastSeen(for: sheet)
                            Button {
                                activeModal = .edit(expense)
                            } label: {
                                ExpenseRowView(expense: expense)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(14)
                                    .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.blue.opacity(isNew ? 0.5 : 0), lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    activeModal = .edit(expense)
                                } label: {
                                    Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: deleteExpenses)
                    }
                } header: {
                    SectionHeader(title: NSLocalizedString("Spese", comment: "expenses"))
                }

                // MARK: Archive link
                if !sheet.settlementsArray.isEmpty {
                    Section {
                        NavigationLink {
                            ArchiveView(sheet: sheet)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "archivebox.fill")
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("archive_title", comment: ""))
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text(String(
                                        format: NSLocalizedString("archive_settlement_count", comment: ""),
                                        sheet.settlementsArray.count
                                    ))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color(.systemBackground))
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(sheet.name ?? NSLocalizedString("sheet", comment: ""))
        .searchable(
            text: $searchText,
            prompt: NSLocalizedString("search_expenses", comment: "")
        )
        .onAppear {
            LastSeenStore.markSeen(for: sheet)
        }
        .toolbar {
            // Azioni secondarie raccolte in un unico menu "•••": con troppi
            // item in barra iOS ne collassa uno in overflow durante la
            // transizione, causando un flash (pulsante che appare/sparisce).
            // Tre item in barra ci stanno larghi → niente overflow, niente flash.
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showStatistics = true
                    } label: {
                        Label(NSLocalizedString("statistics", comment: ""), systemImage: "chart.bar.xaxis")
                    }
                    .disabled(expenses.isEmpty)

                    Button {
                        newPersonName = ""
                        showAddPersonAlert = true
                    } label: {
                        Label(NSLocalizedString("add_person", comment: ""), systemImage: "person.badge.plus")
                    }

                    Button {
                        showSettleConfirm = true
                    } label: {
                        Label(NSLocalizedString("settle_up", comment: ""), systemImage: "checkmark.circle")
                    }
                    .disabled(expenses.isEmpty)

                    Divider()

                    Button {
                        exportPDF()
                    } label: {
                        Label(NSLocalizedString("export_pdf", comment: ""), systemImage: "doc.richtext")
                    }
                    .disabled(expenses.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeModal = .add
                } label: {
                    Image(systemName: "plus")
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                // Tap = invia subito il link (pannello iOS pulito).
                // Long-press = gestione/interruzione condivisione (opzione separata).
                Menu {
                    Button {
                        manageShare()
                    } label: {
                        Label(NSLocalizedString("manage_sharing", comment: ""), systemImage: "person.2")
                    }
                } label: {
                    if isPreparingShare {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                } primaryAction: {
                    openShare()
                }
                .labelStyle(.iconOnly)
            }
        }
        // GESTIONE MODAL AGGIUNGI/MODIFICA/SHARE
        .sheet(item: $activeModal) { modal in
            switch modal {
                case .add:
                    AddExpenseView(sheetID: sheet.objectID)
                case .edit(let expense):
                    AddExpenseView(expenseToEdit: expense)
                case .share(let url):
                    ActivityView(activityItems: [url]) {
                        activeModal = nil
                    }
            }
        }
        // STATISTICHE
        .sheet(isPresented: $showStatistics) {
            StatisticsView(sheet: sheet)
        }
        // TASSO DI CAMBIO
        .sheet(isPresented: $showExchangeRateEditor) {
            ExchangeRateView(sheet: sheet)
                .environment(\.managedObjectContext, viewContext)
        }
        // CONFERMA AZZERAMENTO SALDO
        .confirmationDialog(
            NSLocalizedString("settle_confirm_title", comment: ""),
            isPresented: $showSettleConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("settle_confirm_action", comment: ""), role: .destructive) {
                performSettle()
            }
            Button(NSLocalizedString("Annulla", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("settle_confirm_message", comment: ""))
        }
        // GESTIONE ERRORI CONDIVISIONE
        .alert("Errore condivisione", isPresented: $showingShareError) {
            Button("OK") {}
        } message: {
            Text(shareErrorMessage)
        }
        // GESTIONE ALERT AGGIUNGI PERSONA
        .alert("Aggiungi persona", isPresented: $showAddPersonAlert) {
            TextField("Nome", text: $newPersonName)
            Button("Annulla", role: .cancel) {}
            Button("Aggiungi") { addPerson() }
        } message: {
            Text("Inserisci il nome della persona")
        }
        // CONFERMA IDENTIFICAZIONE PERSONA
        .confirmationDialog(
            NSLocalizedString("identify_confirm_title", comment: ""),
            isPresented: Binding(
                get: { personToClaimAsMe != nil },
                set: { if !$0 { personToClaimAsMe = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let person = personToClaimAsMe {
                Button(String(format: NSLocalizedString("identify_confirm_action", comment: ""), person.name ?? "")) {
                    if let pid = person.id, let sid = sheet.id {
                        currentUser.setPersonID(pid, forSheet: sid)
                    }
                    personToClaimAsMe = nil
                }
            }
            Button(NSLocalizedString("Annulla", comment: ""), role: .cancel) {
                personToClaimAsMe = nil
            }
        } message: {
            if let person = personToClaimAsMe {
                Text(String(format: NSLocalizedString("identify_confirm_message", comment: ""), person.name ?? ""))
            }
        }
    }

    // MARK: - FILTRO

    private var usedCategories: [ExpenseCategory] {
        let raw = Set(expenses.compactMap { $0.category })
        return ExpenseCategory.allCases.filter { raw.contains($0.rawValue) }
    }

    private var filteredExpenses: [Expense] {
        expenses.filter { expense in
            let matchesSearch = searchText.isEmpty
                || (expense.note?.localizedCaseInsensitiveContains(searchText) == true)
                || (expense.paidBy?.name?.localizedCaseInsensitiveContains(searchText) == true)
            let matchesCategory = selectedCategoryFilter == nil
                || expense.category == selectedCategoryFilter?.rawValue
            return matchesSearch && matchesCategory
        }
    }

    // MARK: - AZZERAMENTO SALDO

    private func performSettle() {
        try? SettlementService.performSettlement(sheet: sheet, context: viewContext)
    }

    // MARK: - CONDIVISIONE (CORE)

    // Tap sul tasto condividi: recupera (o crea) il link della share e lo mostra
    // nel pannello di condivisione iOS standard.
    //
    // La share viene PRE-CREATA in background alla creazione del foglio (vedi
    // ShareService/AddSharedSheetView): nel caso normale qui la troviamo già
    // pronta e il pannello è istantaneo. La creazione al tap resta come
    // fallback per i fogli creati con versioni precedenti.
    private func openShare() {
        let container = PersistenceController.shared.container

        if container.viewContext.hasChanges {
            try? container.viewContext.save()
        }

        isPreparingShare = true

        // Timeout di sicurezza: lo spinner non resta mai appeso all'infinito.
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            self.finishShare(error: NSLocalizedString("share_not_synced", comment: ""))
        }

        ShareService.ensureShare(for: sheet.objectID) { result in
            switch result {
                case .success(let url):
                    self.presentShareLink(url)
                case .failure(let error):
                    self.finishShare(error: error.localizedDescription)
            }
        }
    }

    private func presentShareLink(_ url: URL) {
        guard isPreparingShare else { return }
        isPreparingShare = false
        presentViewController(UIActivityViewController(activityItems: [url], applicationActivities: nil))
    }

    private func finishShare(error: String) {
        guard isPreparingShare else { return }
        isPreparingShare = false
        shareErrorMessage = error
        showingShareError = true
    }

    // Long-press: gestione condivisione (partecipanti, permessi, interrompi).
    private func manageShare() {
        let container = PersistenceController.shared.container
        let ckContainer = CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses")

        DispatchQueue.global(qos: .userInitiated).async {
            let existing = (try? container.fetchShares(matching: [self.sheet.objectID]))?[self.sheet.objectID]
            DispatchQueue.main.async {
                guard let existing = existing else {
                    // Niente da gestire: avvia la creazione (flusso link)
                    self.openShare()
                    return
                }
                let controller = UICloudSharingController(share: existing, container: ckContainer)
                controller.delegate = SharingDelegate.shared
                self.presentViewController(controller)
            }
        }
    }

    private func presentViewController(_ controller: UIViewController) {
        guard
            let scene = UIApplication.shared.connectedScenes.first(where: {
                $0.activationState == .foregroundActive
            }) as? UIWindowScene,
            let root = scene.keyWindow?.rootViewController
        else { return }

        var top = root
        while let presented = top.presentedViewController { top = presented }

        // Su iPad i controller sono presentati come popover: àncorali al centro
        if let pop = controller.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }

        top.present(controller, animated: true)
    }

    private func addPerson() {
        let trimmed = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let person = Person(context: viewContext)
        person.id = UUID()
        person.name = trimmed
        person.sheet = sheet

        if let sheetStore = sheet.objectID.persistentStore {
            viewContext.assign(person, to: sheetStore)
        }

        sheet.lastUpdated = Date()
        try? viewContext.save()
    }

    // MARK: - HELPERS

    private func currencySymbol(code: String) -> String {
        let locale = NSLocale(localeIdentifier: NSLocale.localeIdentifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: code]))
        return locale.displayName(forKey: .currencySymbol, value: code) ?? code
    }

    // MARK: - EXPORT PDF

    private func exportPDF() {
        guard !isExportingPDF else { return }
        isExportingPDF = true
        DispatchQueue.global(qos: .userInitiated).async {
            let url = PDFExporter.generate(for: self.sheet)
            DispatchQueue.main.async {
                self.isExportingPDF = false
                let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                self.presentViewController(ac)
            }
        }
    }

    // MARK: - IDENTITÀ FOGLIO CONDIVISO

    private var isSharedSheet: Bool {
        sheet.objectID.persistentStore === persistence.sharedPersistentStore
    }

    /// La persona che sei tu in questo foglio (identità per-foglio + fallback).
    private var myPerson: Person? {
        sheet.resolvedMyPerson(using: currentUser)
    }

    private var isIdentifiedInSheet: Bool {
        myPerson != nil
    }

    // MARK: - LOGICA BILANCI

    private func deleteExpenses(at offsets: IndexSet) {
        offsets.map { expenses[$0] }.forEach(viewContext.delete)
        sheet.lastUpdated = Date()
        try? viewContext.save()
    }

    func balancesPerPerson(sheet: SharedSheet) -> [Person: Double] {
        var balances: [Person: Double] = [:]
        let persons = sheet.personsArray
        let expenses = sheet.activeExpensesArray  // solo spese attive

        persons.forEach { balances[$0] = 0 }

        for expense in expenses {
            guard let payer = expense.paidBy,
                  let split = expense.splitBetween as? Set<Person>,
                  !split.isEmpty else { continue }

            let share = expense.amount / Double(split.count)
            balances[payer, default: 0] += expense.amount
            for person in split {
                balances[person, default: 0] -= share
            }
        }
        return balances
    }

    private func balanceColor(_ value: Double) -> Color {
        if abs(value) < 0.01 { return .secondary }
        return value > 0 ? .green : .red
    }

    func personBalanceText(_ value: Double, isMe: Bool) -> String {
        // Usato solo come label accessibile — testo neutro per qualsiasi persona
        if abs(value) < 0.01 { return NSLocalizedString("In pari", comment: "") }
        let amount = AmountFormatter.format(abs(value))
        return value > 0 ? "\(amount) in credito" : "\(amount) in debito"
    }
}

// MARK: - Supporting Views

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .textCase(nil)
            .foregroundColor(.secondary)
            .listRowBackground(Color.clear)
    }
}

private struct PersonBalanceCard: View {
    let person: Person
    let value: Double
    let isMe: Bool
    let balanceColor: Color
    let balanceText: String
    var onTap: (() -> Void)? = nil

    private var balanceLabel: String {
        if abs(value) < 0.01 { return NSLocalizedString("balance_even_short", comment: "") }
        return value > 0
            ? NSLocalizedString("balance_credit", comment: "")
            : NSLocalizedString("balance_debit", comment: "")
    }

    private var formattedAmount: String {
        if abs(value) < 0.01 { return AmountFormatter.format(0) }
        return AmountFormatter.format(abs(value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isMe ? .blue : .secondary)
                Text(person.name ?? "—")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 4)

            Text(formattedAmount)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(balanceColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(balanceLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(width: 130, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isMe ? Color.blue.opacity(0.25) : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            if onTap != nil {
                Image(systemName: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .padding(6)
            }
        }
        .onTapGesture {
            onTap?()
        }
    }
}

private struct EmptyExpensesView: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text(NSLocalizedString("no_expenses_yet", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .contentShape(Rectangle())
        .onTapGesture { onAdd() }
    }
}

private struct AllSettledEmptyView: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text(NSLocalizedString("all_settled_title", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            Text(NSLocalizedString("all_settled_body", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .contentShape(Rectangle())
        .onTapGesture { onAdd() }
    }
}

private struct SharedSyncEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("shared_sync_empty_title", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            Text(NSLocalizedString("shared_sync_empty_body", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
