import Foundation

public struct AppRow: Identifiable {
    public let id: String
    public let bundleID: String
    public let displayName: String
    public let iconData: Data?
    public let todayCount: Int64
    public let totalCount: Int64

    public init(bundleID: String, displayName: String, iconData: Data?, todayCount: Int64, totalCount: Int64) {
        self.id = bundleID
        self.bundleID = bundleID
        self.displayName = displayName
        self.iconData = iconData
        self.todayCount = todayCount
        self.totalCount = totalCount
    }
}

/// 合并「持久化累计 + 未落盘增量」产出 UI 列表快照。纯函数，可独立测试。
public final class Aggregator {
    public init() {}

    public func produceRows(
        counts: DailyCounts,
        sessionDeltaByBundleID: [String: Int64],
        metadataByBundleID: [String: AppMetadata],
        dayKey: String
    ) -> [AppRow] {
        var bundleIDs = Set(counts.days.values.flatMap { $0.keys })
        bundleIDs.formUnion(sessionDeltaByBundleID.keys)

        return bundleIDs.compactMap { bundleID in
            let persistedTotal = counts.days.values.reduce(Int64(0)) { $0 + ($1[bundleID] ?? 0) }
            let sessionDelta = sessionDeltaByBundleID[bundleID] ?? 0

            let todayCount = (counts.days[dayKey]?[bundleID] ?? 0) + sessionDelta
            let totalCount = persistedTotal + sessionDelta

            guard todayCount > 0 || totalCount > 0 else { return nil }

            let metadata = metadataByBundleID[bundleID]
            return AppRow(
                bundleID: bundleID,
                displayName: metadata?.displayName ?? bundleID,
                iconData: metadata?.iconData,
                todayCount: todayCount,
                totalCount: totalCount
            )
        }
        .sorted { $0.todayCount > $1.todayCount }
    }
}