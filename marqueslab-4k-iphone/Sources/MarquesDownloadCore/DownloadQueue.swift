import Foundation

public enum JobStatus: String, Codable, Sendable {
    case queued, running, converting, done, failed, cancelled

    public var label: String {
        switch self {
        case .queued: return "Na fila"
        case .running: return "Baixando"
        case .converting: return "Convertendo"
        case .done: return "Concluído"
        case .failed: return "Falhou"
        case .cancelled: return "Cancelado"
        }
    }

    public var isFinished: Bool { self == .done || self == .failed || self == .cancelled }
    public var isPending: Bool { self == .queued }
}

public struct DownloadJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var choice: MediaChoice
    public var title: String
    public var status: JobStatus
    public var receivedBytes: Int64
    public var totalBytes: Int64?
    public var bytesPerSecond: Double?
    public var message: String
    public var outputFile: URL?
    /// Set when the file arrived without an audio track, which is a failure for
    /// an editor even though the download itself succeeded.
    public var silent: Bool

    public init(
        id: UUID = UUID(), url: URL, choice: MediaChoice, title: String = "",
        status: JobStatus = .queued, receivedBytes: Int64 = 0, totalBytes: Int64? = nil,
        bytesPerSecond: Double? = nil, message: String = "", outputFile: URL? = nil,
        silent: Bool = false
    ) {
        self.id = id
        self.url = url
        self.choice = choice
        self.title = title
        self.status = status
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.message = message
        self.outputFile = outputFile
        self.silent = silent
    }

    public var displayTitle: String { title.isEmpty ? url.absoluteString : title }

    public var fraction: Double {
        guard let totalBytes, totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }

    public var percent: Int { Int((fraction * 100).rounded()) }
}

/// Ordering and state transitions of the queue, kept free of any UI type so the
/// whole thing is testable without a simulator. The desktop app learned this the
/// hard way: inferring state from the text of a row let a cleanup during a
/// download shift indexes and mark the wrong item as finished.
public struct DownloadQueue: Equatable, Sendable {
    public private(set) var jobs: [DownloadJob]
    public private(set) var activeID: UUID?

    public init(jobs: [DownloadJob] = []) {
        self.jobs = jobs
        self.activeID = nil
    }

    public var active: DownloadJob? { jobs.first { $0.id == activeID } }
    public var isRunning: Bool { activeID != nil }

    @discardableResult
    public mutating func append(url: URL, choice: MediaChoice) -> DownloadJob {
        let job = DownloadJob(url: url, choice: choice)
        jobs.append(job)
        return job
    }

    public mutating func update(_ id: UUID, _ change: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    /// The next job to run, or nil when the queue is idle.
    public mutating func startNext() -> DownloadJob? {
        guard activeID == nil else { return nil }
        guard let index = jobs.firstIndex(where: { $0.status.isPending }) else { return nil }
        jobs[index].status = .running
        jobs[index].receivedBytes = 0
        activeID = jobs[index].id
        return jobs[index]
    }

    public mutating func finish(_ id: UUID, status: JobStatus, message: String = "", file: URL? = nil) {
        update(id) { job in
            job.status = status
            job.bytesPerSecond = nil
            if !message.isEmpty { job.message = message }
            if let file { job.outputFile = file }
            if status == .done, let total = job.totalBytes { job.receivedBytes = total }
        }
        if activeID == id { activeID = nil }
    }

    /// Requeues items the user asked to try again; the active one is untouched.
    public mutating func retry(_ ids: Set<UUID>) -> Int {
        var count = 0
        for index in jobs.indices where ids.contains(jobs[index].id) {
            guard jobs[index].status == .failed || jobs[index].status == .cancelled else { continue }
            jobs[index].status = .queued
            jobs[index].receivedBytes = 0
            jobs[index].message = ""
            count += 1
        }
        return count
    }

    /// Removing never touches the job that is downloading: the caller must
    /// cancel it first, otherwise the transfer would be orphaned.
    @discardableResult
    public mutating func remove(_ ids: Set<UUID>) -> Int {
        let before = jobs.count
        jobs.removeAll { ids.contains($0.id) && $0.id != activeID }
        return before - jobs.count
    }

    @discardableResult
    public mutating func clearFinished() -> Int {
        let before = jobs.count
        jobs.removeAll { $0.status.isFinished && $0.id != activeID }
        return before - jobs.count
    }
}
