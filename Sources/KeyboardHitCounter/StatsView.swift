import SwiftUI
import AppKit
import KeyboardHitCounterCore

public struct StatsView: View {
    @ObservedObject var viewModel: StatsViewModel

    public init(viewModel: StatsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            StatsPeriodView(
                rows: viewModel.snapshot.todayRows,
                emptyMessage: "今日暂无记录"
            )
            .tabItem { Text("每日") }

            StatsPeriodView(
                rows: viewModel.snapshot.weekRows,
                emptyMessage: "本周暂无记录"
            )
            .tabItem { Text("每周") }

            StatsPeriodView(
                rows: viewModel.snapshot.totalRows,
                emptyMessage: "暂无记录"
            )
            .tabItem { Text("总计") }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 480)
    }
}

/// 单个统计口径（今日/本周/总计）的应用分布列表。
private struct StatsPeriodView: View {
    let rows: [StatsRow]
    let emptyMessage: String

    var body: some View {
        if rows.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            StatsRowList(rows: rows)
        }
    }
}

private struct StatsRowList: View {
    let rows: [StatsRow]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    StatsRowView(row: row)
                }
            }
        }
    }
}

private struct StatsRowView: View {
    let row: StatsRow

    var body: some View {
        HStack(spacing: 8) {
            icon
            Text(row.displayName).lineLimit(1)
            Spacer()
            Text("\(row.count)")
                .font(.system(.headline, design: .monospaced))
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var icon: some View {
        if let data = row.iconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
