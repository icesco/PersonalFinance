import Foundation
import Testing
@testable import FinanceCore

@MainActor struct CaptureClassificationTests {
    @Test func walletRecognizesAmericanExpressAndAmexBeforeGenericDefaultAndHistory() {
        let bank = account("Banca")
        let card = account("Carta di credito American Express")
        card.type = .credit
        let setting = CaptureBankDefault(bank: "Wallet", bookID: bank.account!.id, contoID: bank.id)
        for name in ["American Express", "AMEX"] {
            let result = CaptureClassifier.suggest(destination: "", source: "Wallet",
                text: "\(name)\nPagamento EUR 20 presso Esselunga", type: .expense,
                conti: [bank, card], history: [movement(bank, category: nil), movement(bank, category: nil)],
                bankDefaults: [setting], isBankNotification: true)
            #expect(result.contoID == card.id)
            #expect(result.bookID == card.account?.id)
            #expect(result.accountReason == "Carta riconosciuta nella notifica Wallet")
        }
    }

    @Test func walletMatchesOtherExistingCardNamesAndWordBoundaries() {
        let bank = account("Banca")
        let card = account("Carta Revolut")
        let result = CaptureClassifier.suggest(destination: "", source: "Apple Wallet", text: "Revolut\nEUR 20 presso Esselunga",
            type: .expense, conti: [bank, card], history: [], isBankNotification: true)
        #expect(result.contoID == card.id)
        let partial = CaptureClassifier.suggest(destination: "", source: "Wallet", text: "Revolutivo\nEUR 20 presso Esselunga",
            type: .expense, conti: [bank, card], history: [], isBankNotification: true)
        #expect(partial.contoID == nil)
    }

    @Test func walletSpecificCardNameDisambiguatesAnIssuer() {
        let generic = account("American Express")
        let gold = account("American Express Gold")
        let result = CaptureClassifier.suggest(destination: "", source: "Wallet", text: "Amex Gold\nEUR 20",
            type: .expense, conti: [generic, gold], history: [], isBankNotification: true)
        #expect(result.contoID == gold.id)
    }

    @Test func ambiguousWalletCardDoesNotFallBackToDefaultOrHistory() {
        let bank = account("Banca")
        let first = account("American Express Gold")
        let second = account("Amex Blu", bookName: "Lavoro")
        let setting = CaptureBankDefault(bank: "Wallet", bookID: bank.account!.id, contoID: bank.id)
        let result = CaptureClassifier.suggest(destination: "", source: "Wallet", text: "American Express\nEUR 20 presso Esselunga",
            type: .expense, conti: [bank, first, second], history: [movement(bank, category: nil), movement(bank, category: nil)],
            bankDefaults: [setting], isBankNotification: true)
        #expect(result.contoID == nil)
        #expect(result.accountReason?.contains("Più conti") == true)
        let scoped = CaptureClassifier.suggest(destination: "", source: "Wallet", text: "American Express\nEUR 20",
            type: .expense, conti: [bank, first, second], history: [], selectedBookID: second.account?.id, isBankNotification: true)
        #expect(scoped.contoID == second.id)
    }

    @Test func explicitAndManualDestinationsWinOverWalletEvidence() {
        let bank = account("Banca")
        let card = account("American Express")
        let explicit = CaptureClassifier.suggest(destination: "Banca", source: "Wallet", text: "American Express\nEUR 20",
            type: .expense, conti: [bank, card], history: [], isBankNotification: true)
        #expect(explicit.contoID == bank.id)
        let manual = CaptureClassifier.suggest(destination: "", source: "Wallet", text: "American Express\nEUR 20",
            type: .expense, conti: [bank, card], history: [], selectedContoID: bank.id, isBankNotification: true)
        #expect(manual.contoID == bank.id)
        #expect(manual.accountReason == nil)
    }

    @Test func missingOrInactiveWalletCardDoesNotChooseAnUnrelatedSingleAccount() {
        let bank = account("Banca")
        let card = account("American Express")
        card.isActive = false
        let result = CaptureClassifier.suggest(destination: "", source: "Wallet", text: "Amex\nEUR 20",
            type: .expense, conti: [bank, card], history: [], selectedBookID: bank.account?.id, isBankNotification: true)
        #expect(result.contoID == nil)
        #expect(result.accountReason?.contains("non associata") == true)
    }

    @Test func walletDoesNotUseMerchantNamesOrApplyCardInferenceToSharedDocuments() {
        let bank = account("Banca")
        let card = account("American Express")
        let merchant = CaptureClassifier.suggest(destination: "", source: "Wallet", text: "Pagamento EUR 20 presso American Express Travel",
            type: .expense, conti: [bank, card], history: [], isBankNotification: true)
        #expect(merchant.contoID == nil)
        let shared = CaptureClassifier.suggest(destination: "", source: "Wallet", text: "Amex\nEUR 20",
            type: .expense, conti: [bank, card], history: [])
        #expect(shared.contoID == nil)
    }

    @Test func conflictingWalletNamesStayAmbiguous() {
        let first = account("Revolut")
        let second = account("American Express")
        let result = CaptureClassifier.suggest(destination: "", source: "Wallet", text: "Revolut\nAmerican Express\nEUR 20",
            type: .expense, conti: [first, second], history: [], isBankNotification: true)
        #expect(result.contoID == nil)
    }
    @Test func onlyAvailableDestinationIsSelectedWithoutHistory() {
        let conto = account("Conto corrente")
        let result = CaptureClassifier.suggest(destination: "", source: "Mail", text: "EUR 20", type: .expense, conti: [conto], history: [])
        #expect(result.bookID == conto.account?.id && result.contoID == conto.id)
        #expect(result.accountReason == "Unico libro e conto disponibili")
        let second = Conto(name: "Contanti", type: .cash)
        second.account = conto.account
        #expect(CaptureClassifier.suggest(destination: "", source: "Mail", text: "EUR 20", type: .expense, conti: [conto, second], history: []).contoID == nil)
    }
    @Test func bankDefaultWinsOverSourceNameAndHistoryButNotExplicitDestination() {
        let personal = account("Revolut")
        let work = account("Aziendale", bookName: "Lavoro")
        let setting = CaptureBankDefault(bank: " Revolut ", bookID: work.account!.id, contoID: work.id)
        let history = [movement(personal, category: nil), movement(personal, category: nil)]
        let suggested = CaptureClassifier.suggest(destination: "", source: "REVOLUT", text: "EUR 20 presso Esselunga", type: .expense,
            conti: [personal, work], history: history, bankDefaults: [setting], isBankNotification: true)
        #expect(suggested.contoID == work.id)
        #expect(suggested.accountReason?.contains("Conto predefinito") == true)
        let explicit = CaptureClassifier.suggest(destination: "Revolut", source: "Revolut", text: "EUR 20", type: .expense,
            conti: [personal, work], history: [], bankDefaults: [setting], isBankNotification: true)
        #expect(explicit.contoID == personal.id)
        let missing = CaptureClassifier.suggest(destination: "Non esiste", source: "Revolut", text: "EUR 20", type: .expense,
            conti: [personal, work], history: [], bankDefaults: [setting], isBankNotification: true)
        #expect(missing.contoID == nil)
        let review = CaptureClassifier.suggest(destination: "", source: "Revolut", text: "EUR 20", type: .expense,
            conti: [personal, work], history: [], selectedBookID: work.account?.id, selectedContoID: work.id,
            bankDefaults: [setting], isBankNotification: true)
        #expect(review.accountReason?.contains("Conto predefinito") == true)
    }
    @Test func unavailableDefaultDoesNotFallBackAndShareDoesNotUseBankDefaults() {
        let conto = account("Banca")
        let setting = CaptureBankDefault(bank: "Mail", bookID: UUID(), contoID: UUID())
        let notification = CaptureClassifier.suggest(destination: "", source: "Mail", text: "EUR 20", type: .expense,
            conti: [conto], history: [], bankDefaults: [setting], isBankNotification: true)
        #expect(notification.contoID == nil)
        #expect(notification.accountReason?.contains("non disponibile") == true)
        let shared = CaptureClassifier.suggest(destination: "", source: "Mail", text: "EUR 20", type: .expense,
            conti: [conto], history: [], bankDefaults: [setting])
        #expect(shared.contoID == conto.id)
        let inactive = CaptureBankDefault(bank: "Banca", bookID: conto.account!.id, contoID: conto.id)
        conto.isActive = false
        #expect(CaptureClassifier.suggest(destination: "", source: "Banca", text: "EUR 20", type: .expense,
            conti: [conto], history: [], bankDefaults: [inactive], isBankNotification: true).contoID == nil)
    }
    private func account(_ name: String, bookName: String = "Personale") -> Conto {
        let book = Account(name: bookName, currency: "EUR")
        let conto = Conto(name: name, type: .checking)
        conto.account = book; book.conti = [conto]
        return conto
    }
    private func movement(_ conto: Conto, category: FinanceCore.Category?, type: TransactionType = .expense) -> Transaction {
        let transaction = Transaction(amount: 20, type: type, transactionDescription: "Esselunga")
        if type == .expense { transaction.setFromConto(conto) } else { transaction.setToConto(conto) }
        transaction.setCategory(category)
        return transaction
    }
    @Test func repeatedMerchantSuggestsActualBookAccountAndCategory() {
        let conto = account("Banca")
        let category = FinanceCore.Category(name: "Alimentari", kind: .expense)
        category.account = conto.account; conto.account?.categories = [category]
        let result = CaptureClassifier.suggest(destination: "", source: "Mail", text: "EUR 20 presso ESSELUNGA", type: .expense,
            conti: [conto], history: [movement(conto, category: category), movement(conto, category: category)])
        #expect(result.bookID == conto.account?.id)
        #expect(result.contoID == conto.id)
        #expect(result.categoryID == category.id)
        #expect(result.categoryReason != nil)
    }
    @Test func ambiguousDestinationRequiresBookSelection() {
        let personal = account("Banca")
        let work = account("Banca", bookName: "Lavoro")
        let history = [movement(personal, category: nil), movement(personal, category: nil)]
        let unclear = CaptureClassifier.suggest(destination: "Banca", source: "Banca", text: "EUR 20 presso Esselunga", type: .expense, conti: [personal, work], history: history)
        #expect(unclear.bookID == nil && unclear.contoID == nil)
        let scoped = CaptureClassifier.suggest(destination: "Banca", source: "Banca", text: "EUR 20 presso Esselunga", type: .expense, conti: [personal, work], history: history, selectedBookID: work.account?.id)
        #expect(scoped.contoID == work.id && scoped.bookID == work.account?.id)
    }
    @Test func conflictingHistoryDoesNotChooseCategory() {
        let conto = account("Banca")
        let first = FinanceCore.Category(name: "Alimentari", kind: .expense)
        let second = FinanceCore.Category(name: "Regali", kind: .expense)
        for category in [first, second] { category.account = conto.account }
        conto.account?.categories = [first, second]
        let result = CaptureClassifier.suggest(destination: "Banca", source: "Banca", text: "EUR 20 presso Esselunga", type: .expense,
            conti: [conto], history: [movement(conto, category: first), movement(conto, category: second)])
        #expect(result.contoID == conto.id)
        #expect(result.categoryID == nil)
    }
    @Test func unknownDestinationAndInactiveAccountAreNotGuessed() {
        let conto = account("Banca")
        let history = [movement(conto, category: nil), movement(conto, category: nil)]
        let missing = CaptureClassifier.suggest(destination: "Altra banca", source: "Banca", text: "EUR 20 presso Esselunga", type: .expense, conti: [conto], history: history)
        #expect(missing.contoID == nil)
        conto.isActive = false
        let inactive = CaptureClassifier.suggest(destination: "Banca", source: "Banca", text: "EUR 20 presso Esselunga", type: .expense, conti: [conto], history: history)
        #expect(inactive.contoID == nil)
    }
    @Test func categoryWordsAreScopedToBookAndTransactionKind() {
        let conto = account("Banca")
        let income = FinanceCore.Category(name: "Stipendio", kind: .income)
        income.account = conto.account; conto.account?.categories = [income]
        let expense = CaptureClassifier.suggest(destination: "Banca", source: "Banca", text: "Stipendio EUR 20", type: .expense, conti: [conto], history: [])
        #expect(expense.categoryID == nil)
        let result = CaptureClassifier.suggest(destination: "Banca", source: "Banca", text: "Stipendio EUR 20", type: .income, conti: [conto], history: [])
        #expect(result.categoryID == income.id)
    }
}
