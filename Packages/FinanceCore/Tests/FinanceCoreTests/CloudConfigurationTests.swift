import Testing
import SwiftData
@testable import FinanceCore

struct CloudConfigurationTests {
    @Test func localAndPreviewStoresExplicitlyDisableCloudKit() {
        let local = FinanceCoreModule.createModelConfiguration(enableCloudKit: false)
        let preview = FinanceCoreModule.createModelConfiguration(enableCloudKit: true, inMemory: true)
        #expect(preview.cloudKitContainerIdentifier == nil)
        #expect(local.cloudKitContainerIdentifier == nil)
    }

    @Test func cloudStoreRequiresExplicitOptIn() {
        let cloud = FinanceCoreModule.createModelConfiguration(enableCloudKit: true)
        #expect(cloud.cloudKitContainerIdentifier == FinanceCoreModule.cloudKitContainerIdentifier)
        let local = FinanceCoreModule.createModelConfiguration(enableCloudKit: false)
        #expect(local.url == cloud.url)
    }
}
