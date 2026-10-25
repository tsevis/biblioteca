import Foundation
import Testing

@Suite("Run progress")
struct ProgressTests {
    private func job(_ status: ConversionJob.Status) -> ConversionJob {
        ConversionJob(source: URL(fileURLWithPath: "/books/\(UUID().uuidString).epub")).with(status: status)
    }

    @Test("Finished, failed and skipped books count whole; the running one by its own fraction")
    func overallProgress() {
        let jobs = [job(.finished(URL(fileURLWithPath: "/out/a.pdf"))), job(.failed("broken")),
                    job(.skipped("Already converted")), job(.converting(progress: 0.5)), job(.waiting)]
        #expect(ConversionJob.overallProgress(of: jobs) == 3.5 / 5)
    }
}
