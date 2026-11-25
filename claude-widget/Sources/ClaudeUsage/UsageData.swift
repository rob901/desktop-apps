import Foundation

/// One reading of plan usage, as percentages of the limits (0–100).
struct UsageSample {
    let date: Date
    let session: Double?   // current 5-hour session window
    let week: Double?      // rolling 7-day window
}

enum UsageMetric {
    case session, week

    func value(_ s: UsageSample) -> Double? {
        switch self {
        case .session: return s.session
        case .week: return s.week
        }
    }
}

/// The widget's two views: session usage over the last day, weekly usage over the last week.
enum ChartRange: String, Codable, CaseIterable {
    case day, week

    var metric: UsageMetric { self == .day ? .session : .week }
    var span: TimeInterval { self == .day ? 24 * 3600 : 7 * 24 * 3600 }
    /// Samples further apart than this aren't joined by a line: we don't know what happened between them.
    var maxGap: TimeInterval { self == .day ? 45 * 60 : 12 * 3600 }
    var label: String { self == .day ? "Day" : "Week" }
    var chartTitle: String { self == .day ? "Session usage · last 24 hours" : "Weekly usage · last 7 days" }
}

/// Reads the plan-usage history the Claude desktop app keeps while it runs:
/// `~/Library/Application Support/Claude/plan-usage-history.json`, a list of samples
/// `{t: ms since 1970, org: id, u: {fh: 5-hour %, sd: 7-day %}}` taken every 5–15 minutes.
/// It's an internal file of that app, so it's read defensively: anything unexpected
/// becomes an error message in the widget, never a crash.
final class UsageSource {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")

    let url: URL
    private(set) var samples: [UsageSample] = []   // oldest first, one organization
    private(set) var problem: String?              // why there's no data, if there isn't
    private var lastModified: Date?

    init(url: URL = UsageSource.defaultURL) {
        self.url = url
    }

    var latest: UsageSample? { samples.last }

    /// Re-reads the file if it changed since the last read. Returns true if anything changed.
    @discardableResult
    func reloadIfChanged() -> Bool {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard let modified else {
            let changed = lastModified != nil || problem == nil
            lastModified = nil
            samples = []
            problem = "No usage data yet. Open the Claude app and sign in; it records your usage while it runs."
            return changed
        }
        if modified == lastModified { return false }
        lastModified = modified
        load()
        return true
    }

    private func load() {
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(HistoryFile.self, from: data)
            // If more than one account shows up, follow the one used most recently.
            let org = file.samples.max(by: { $0.t < $1.t })?.org
            samples = file.samples
                .filter { $0.org == org }
                .map { UsageSample(date: Date(timeIntervalSince1970: $0.t / 1000),
                                   session: $0.u?.fh.map(clamp), week: $0.u?.sd.map(clamp)) }
                .sorted { $0.date < $1.date }
            problem = samples.isEmpty ? "The Claude app hasn't recorded any usage yet." : nil
        } catch {
            samples = []
            problem = "Couldn't read the Claude app's usage file. Its format may have changed."
            NSLog("ClaudeUsage: could not read \(url.path): \(error)")
        }
    }

    private func clamp(_ v: Double) -> Double { min(100, max(0, v)) }

    /// Samples inside the range ending now, for one metric, split wherever readings are missing.
    func segments(for range: ChartRange, now: Date = Date()) -> [[(date: Date, value: Double)]] {
        let start = now.addingTimeInterval(-range.span)
        var result: [[(date: Date, value: Double)]] = []
        var current: [(date: Date, value: Double)] = []
        for s in samples where s.date >= start && s.date <= now {
            guard let v = range.metric.value(s) else { continue }
            if let last = current.last, s.date.timeIntervalSince(last.date) > range.maxGap {
                result.append(current)
                current = []
            }
            current.append((s.date, v))
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private struct HistoryFile: Decodable {
        let samples: [Raw]
        struct Raw: Decodable {
            let t: Double
            let org: String?
            let u: Values?
        }
        struct Values: Decodable {
            let fh: Double?
            let sd: Double?
        }
    }
}
