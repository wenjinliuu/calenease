import SwiftUI
import UniformTypeIdentifiers

/// 备份与恢复。数据只在本机，换设备或清数据前先导出一份。
struct BackupView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.showToast) private var showToast

    @State private var exportURL: URL?
    @State private var isImporterPresented = false
    @State private var pendingImport: ScheduleDocument?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        prepareExport()
                    } label: {
                        Label("生成备份文件", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    isImporterPresented = true
                } label: {
                    Label("导入备份", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("JSON 备份")
            } footer: {
                Text("备份包含自定义班次、标签、循环、工时规则和每日记录，与网页版格式一致，可以互相导入。")
            }

            Section("状态") {
                LabeledContent("记录天数", value: "\(store.document.records.count) 天")
                LabeledContent("班次 / 标签",
                               value: "\(store.document.shifts.count) / \(store.document.tags.count)")
                LabeledContent("上次导出", value: lastBackupText)
            }

            Section {
                Label("数据只保存在这台设备上，不上传服务器；卸载 App 会一并删除。开启 iCloud 备份时，系统备份里会包含这份数据。",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .pageBackground()
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isImporterPresented,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    pendingImport = try BackupService.decode(contentsOf: url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("导入失败", isPresented: Binding(get: { errorMessage != nil },
                                            set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("导入会覆盖当前全部数据，确定继续吗？",
                            isPresented: Binding(get: { pendingImport != nil },
                                                 set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible) {
            Button("覆盖并导入", role: .destructive) {
                guard let pendingImport else { return }
                store.replaceDocument(pendingImport)
                showToast("已导入 \(pendingImport.records.count) 天记录")
                self.pendingImport = nil
                exportURL = nil
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        } message: {
            if let pendingImport {
                Text("这份备份包含 \(pendingImport.records.count) 天记录、\(pendingImport.shifts.count) 个班次。")
            }
        }
        .onChange(of: store.document) { _, _ in
            // 数据变了，旧的备份文件就过期了
            exportURL = nil
        }
    }

    private var lastBackupText: String {
        guard let days = preferences.daysSinceBackup else { return "从未导出" }
        return days == 0 ? "今天" : "\(days) 天前"
    }

    private func prepareExport() {
        do {
            exportURL = try BackupService.writeTemporaryFile(store.document)
            preferences.lastBackupAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
