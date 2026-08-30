import Foundation

/// 统计页面的一行数据：某应用在某统计口径（今日/本周/总计）下的计数。
public struct StatsRow: Identifiable, Equatable {
    public let bundleID: String
    public let displayName: String
    public let iconData: Data?
    public let count: Int64

    public var id: String { bundleID }

    public init(bundleID: String, displayName: String, iconData: Data?, count: Int64) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.iconData = iconData
        self.count = count
    }
}

public struct StatsSnapshot: Equatable {
    public let todayRows: [StatsRow]
    public let weekRows: [StatsRow]
    public let totalRows: [StatsRow]

    public static let empty = StatsSnapshot(
        todayRows: [], weekRows: [], totalRows: []
    )

    public init(
        todayRows: [StatsRow],
        weekRows: [StatsRow],
        totalRows: [StatsRow]
    ) {
        self.todayRows = todayRows
        self.weekRows = weekRows
        self.totalRows = totalRows
    }
}

/// 把「持久化累计 + 未落盘增量」聚合成统计页面所需的今日/本周/总计。纯函数，无 I/O，可独立测试。
public final class StatsAggregator {
    public init() {}

    public func produceSnapshot(
        counts: DailyCounts,
        sessionDeltaByBundleID: [String: Int64],
        metadataByBundleID: [String: AppMetadata],
        now: Date = Date()
    ) -> StatsSnapshot {
        let todayKey = PersistenceWorker.dayKey(now: now)
        let weekOfToday = Self.weekKey(for: now)
        let weekKeyByDayKey = Self.weekKeyByDayKeyCache(dayKeys: counts.days.keys, now: now)

        let totalsByBundleID = Self.sumAllDays(counts: counts, sessionDeltaByBundleID: sessionDeltaByBundleID)
        let todayTotals = Self.sumDays(
            counts: counts,
            matching: { $0 == todayKey },
            sessionDeltaByBundleID: sessionDeltaByBundleID,
            applySessionDelta: true
        )
        let weekTotals = Self.sumDays(
            counts: counts,
            matching: { weekKeyByDayKey[$0] == weekOfToday },
            sessionDeltaByBundleID: sessionDeltaByBundleID,
            applySessionDelta: true
        )

        return StatsSnapshot(
            todayRows: Self.rows(from: todayTotals, metadataByBundleID: metadataByBundleID),
            weekRows: Self.rows(from: weekTotals, metadataByBundleID: metadataByBundleID),
            totalRows: Self.rows(from: totalsByBundleID, metadataByBundleID: metadataByBundleID)
        )
    }

    // MARK: - 汇总

    private static func sumAllDays(
        counts: DailyCounts,
        sessionDeltaByBundleID: [String: Int64]
    ) -> [String: Int64] {
        sumDays(counts: counts, matching: { _ in true }, sessionDeltaByBundleID: sessionDeltaByBundleID, applySessionDelta: true)
    }

    private static func sumDays(
        counts: DailyCounts,
        matching predicate: (String) -> Bool,
        sessionDeltaByBundleID: [String: Int64],
        applySessionDelta: Bool
    ) -> [String: Int64] {
        var totals: [String: Int64] = [:]
        for (dayKey, dayCounts) in counts.days where predicate(dayKey) {
            for (bundleID, count) in dayCounts {
                totals[bundleID, default: 0] += count
            }
        }
        if applySessionDelta {
            for (bundleID, delta) in sessionDeltaByBundleID where delta > 0 {
                totals[bundleID, default: 0] += delta
            }
        }
        return totals
    }

    private static func rows(
        from totals: [String: Int64],
        metadataByBundleID: [String: AppMetadata]
    ) -> [StatsRow] {
        totals
            .filter { $0.value > 0 }
            .map { bundleID, count in
                let metadata = metadataByBundleID[bundleID]
                return StatsRow(
                    bundleID: bundleID,
                    displayName: metadata?.displayName ?? bundleID,
                    iconData: metadata?.iconData,
                    count: count
                )
            }
            // 次数降序，次数相同时以 bundleID 兜底，保证排序确定、稳定。
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.bundleID < $1.bundleID }
    }

    // MARK: - 日期/周期计算

    /// 给定一批已知的 dayKey，预先算出各自的 weekKey，避免重复解析日期字符串。
    private static func weekKeyByDayKeyCache<S: Sequence>(dayKeys: S, now: Date) -> [String: String] where S.Element == String {
        var cache: [String: String] = [:]
        for dayKey in dayKeys {
            cache[dayKey] = weekKey(for: dayDate(from: dayKey) ?? now)
        }
        return cache
    }

    static func weekKey(for date: Date) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    private static func dayDate(from dayKey: String) -> Date? {
        dayKeyFormatter.date(from: dayKey)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}
