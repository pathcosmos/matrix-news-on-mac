import Foundation
import Testing

@Suite("Update news workflow")
struct UpdateNewsWorkflowTests {
    @Test("scheduled update keeps a fifty item floor every ten minutes")
    func scheduledUpdateKeepsFiftyItemFloorEveryTenMinutes() throws {
        let workflowURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".github/workflows/update-news.yml")
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)

        #expect(workflow.contains("cron: \"*/10 * * * *\""))
        #expect(workflow.contains("--limit 50"))
        #expect(workflow.contains("--minimum-items 50"))
        #expect(workflow.contains("Data/manifest.json Data/latest.json Data/sources.json"))
    }
}
