import SwiftUI
import AppKit
import KeyboardHitCounterCore

public struct StatusView: View {
    @ObservedObject var viewModel: StatusViewModel
    let onOpenSettings: () -> Void

    public init(viewModel: StatusViewModel, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.permissionState == .denied {
                deniedView
            } else if viewModel.rows.isEmpty {
                emptyView
            } else {
                list
            }
        }
        .frame(width: 320)
        .padding(8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.rows) { row in
                    RowView(row: row)
                }
            }
        }
    }

    private var emptyView: some View {
        Text("暂无记录")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("需要「辅助功能」权限").font(.headline)
            Text("用于监听全局键盘事件，授权后自动开始计数。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("打开系统设置", action: onOpenSettings)
        }
        .padding(.vertical, 8)
    }
}

private struct RowView: View {
    let row: AppRow

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName).lineLimit(1)
                Text("累计 \(row.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(row.todayCount)")
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