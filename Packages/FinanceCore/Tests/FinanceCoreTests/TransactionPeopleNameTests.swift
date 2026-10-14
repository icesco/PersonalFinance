import Foundation
import Testing
@testable import FinanceCore

struct TransactionPeopleNameTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "TransactionPeopleNameTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func cloudNameFillsAnEmptyFieldAndMarksItsSource() {
        withDefaults { defaults in
            TransactionPeople.cacheCloudIdentity("person-a", defaults: defaults)
            TransactionPeople.fillDisplayNameIfEmpty(.init(id: "person-a", name: "  Anna Bianchi \n"), defaults: defaults)
            #expect(defaults.string(forKey: "formi.personDisplayName") == "Anna Bianchi")
            #expect(defaults.string(forKey: "formi.cloudPersonDisplayName") == "Anna Bianchi")
        }
    }

    @Test func lateCloudNameDoesNotReplaceManualInput() {
        withDefaults { defaults in
            TransactionPeople.cacheCloudIdentity("person-a", defaults: defaults)
            TransactionPeople.setDisplayName("Anna", defaults: defaults)
            TransactionPeople.fillDisplayNameIfEmpty(.init(id: "person-a", name: "Anna Bianchi"), defaults: defaults)
            #expect(defaults.string(forKey: "formi.personDisplayName") == "Anna")
            #expect(defaults.string(forKey: "formi.cloudPersonDisplayName") == nil)
        }
    }

    @Test func missingAndWrongAccountNamesLeaveTheFieldEmpty() {
        withDefaults { defaults in
            TransactionPeople.cacheCloudIdentity("person-a", defaults: defaults)
            TransactionPeople.fillDisplayNameIfEmpty(.init(id: "person-a", name: " \n"), defaults: defaults)
            TransactionPeople.fillDisplayNameIfEmpty(.init(id: "person-b", name: "Un’altra persona"), defaults: defaults)
            #expect(defaults.string(forKey: "formi.personDisplayName") == nil)
        }
    }

    @Test func changingAccountsClearsAutomaticNamesButPreservesManualNames() {
        withDefaults { defaults in
            TransactionPeople.cacheCloudIdentity("person-a", defaults: defaults)
            TransactionPeople.fillDisplayNameIfEmpty(.init(id: "person-a", name: "Anna"), defaults: defaults)
            TransactionPeople.cacheCloudIdentity("person-b", defaults: defaults)
            #expect(defaults.string(forKey: "formi.personDisplayName") == nil)
            TransactionPeople.fillDisplayNameIfEmpty(.init(id: "person-b", name: "Marco"), defaults: defaults)
            TransactionPeople.setDisplayName("Nome scelto", defaults: defaults)
            TransactionPeople.clearCloudIdentity(defaults: defaults)
            #expect(defaults.string(forKey: "formi.personDisplayName") == "Nome scelto")
            #expect(defaults.string(forKey: "formi.cloudPersonDisplayName") == nil)
        }
    }
}
