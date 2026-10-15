import SwiftData
import Testing
@testable import BulkBoard

@Suite("Persistence")
struct PersistenceTests {
    @Test func inMemoryContainerOpens() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(WeightRecord(date: .now, weightKg: 82))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<WeightRecord>()) == 1)
    }
}
