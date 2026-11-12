import XCTest
@testable import MarquesDownloadCore

final class DownloadQueueTests: XCTestCase {
    func url(_ s: String) -> URL { URL(string: s)! }

    func makeQueue(_ count: Int) -> DownloadQueue {
        var queue = DownloadQueue()
        for index in 0..<count {
            queue.append(url: url("https://example.com/\(index)"), choice: .video(.p1080))
        }
        return queue
    }

    func testStartsTheFirstPendingJob() {
        var queue = makeQueue(3)
        let started = queue.startNext()
        XCTAssertEqual(started?.url.absoluteString, "https://example.com/0")
        XCTAssertEqual(queue.active?.status, .running)
        XCTAssertTrue(queue.isRunning)
    }

    func testDoesNotStartASecondJobWhileOneRuns() {
        var queue = makeQueue(2)
        _ = queue.startNext()
        XCTAssertNil(queue.startNext(), "a fila é sequencial")
    }

    func testFinishingReleasesTheQueue() {
        var queue = makeQueue(2)
        let first = queue.startNext()!
        queue.finish(first.id, status: .done, file: url("file:///tmp/a.mp4"))

        XCTAssertFalse(queue.isRunning)
        XCTAssertEqual(queue.jobs[0].status, .done)
        XCTAssertEqual(queue.jobs[0].outputFile?.lastPathComponent, "a.mp4")
        XCTAssertEqual(queue.startNext()?.url.absoluteString, "https://example.com/1")
    }

    func testClearFinishedKeepsPendingAndActive() {
        var queue = makeQueue(3)
        let active = queue.startNext()!
        queue.finish(active.id, status: .done)
        let second = queue.startNext()!

        XCTAssertEqual(queue.clearFinished(), 1)
        XCTAssertEqual(queue.jobs.count, 2)
        XCTAssertEqual(queue.active?.id, second.id, "o item em download não pode sumir")
    }

    func testRemoveNeverDropsTheActiveJob() {
        var queue = makeQueue(2)
        let active = queue.startNext()!
        let all = Set(queue.jobs.map(\.id))

        XCTAssertEqual(queue.remove(all), 1)
        XCTAssertEqual(queue.jobs.map(\.id), [active.id])
        XCTAssertEqual(queue.active?.id, active.id)
    }

    func testRetryOnlyRequeuesFailedAndCancelled() {
        var queue = makeQueue(3)
        queue.finish(queue.jobs[0].id, status: .done)
        queue.finish(queue.jobs[1].id, status: .failed, message: "erro")
        queue.finish(queue.jobs[2].id, status: .cancelled)

        XCTAssertEqual(queue.retry(Set(queue.jobs.map(\.id))), 2)
        XCTAssertEqual(queue.jobs.map(\.status), [.done, .queued, .queued])
        XCTAssertTrue(queue.jobs[1].message.isEmpty, "a mensagem antiga some ao reenfileirar")
    }

    func testProgressMath() {
        var queue = makeQueue(1)
        let job = queue.startNext()!
        queue.update(job.id) { $0.totalBytes = 1_000; $0.receivedBytes = 250 }

        XCTAssertEqual(queue.jobs[0].percent, 25)
        XCTAssertEqual(queue.jobs[0].fraction, 0.25, accuracy: 0.001)
    }

    func testProgressIsZeroWithoutATotal() {
        var queue = makeQueue(1)
        let job = queue.startNext()!
        queue.update(job.id) { $0.receivedBytes = 999 }
        XCTAssertEqual(queue.jobs[0].percent, 0)
    }

    func testDoneJobReadsAsComplete() {
        var queue = makeQueue(1)
        let job = queue.startNext()!
        queue.update(job.id) { $0.totalBytes = 500; $0.receivedBytes = 10 }
        queue.finish(job.id, status: .done)
        XCTAssertEqual(queue.jobs[0].percent, 100)
    }

    func testDisplayTitleFallsBackToTheURL() {
        var queue = makeQueue(1)
        XCTAssertEqual(queue.jobs[0].displayTitle, "https://example.com/0")
        queue.update(queue.jobs[0].id) { $0.title = "Set Guanabara" }
        XCTAssertEqual(queue.jobs[0].displayTitle, "Set Guanabara")
    }

    func testEmptyQueueStartsNothing() {
        var queue = DownloadQueue()
        XCTAssertNil(queue.startNext())
        XCTAssertFalse(queue.isRunning)
    }
}
