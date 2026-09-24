import SwiftUI
import UniformTypeIdentifiers

/// 备份与恢复：自动备份（iCloud / 本机）、备份文件管理、JSON 导出导入。
struct BackupView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(BackupCenter.self) private var backups
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.showToast) private var showToast

    @State private var exportURL: URL?
    @State private var isImporterPresented = false
    @State private var pendingImport: ScheduleDocument?
    @State private var pendingRestore: BackupItem?
    @State private var pendingDelete: BackupItem?
    @State private var shareItem: ShareFile?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var backups = backups
        Form {
            Section {
                Toggle("自动备份", isOn: $backups.autoEnabled)
                if backups.autoEnabled {
                    Picker("备份频率", selection: $backups.frequency) {
                        ForEach(BackupFrequency.allCases) { Text($0.label).tag($0) }
                    }
                }
                Toggle("备份到 iCloud", isOn: $backups.useICloud)
                LabeledContent("上次自动备份", value: lastAutoText)
                Button {
                    Task { await backupNow() }
                } label: {
                    Label("立即备份", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(isWorking)
            } header: {
                Text("自动备份")
            } footer: {
                Text(autoFooter)
            }

            if let issue = backups.cloudIssue, backups.useICloud {
                Section {
                    Label(issue, systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if backups.items.isEmpty {
                    Text(backups.isLoading ? "正在读取…" : "还没有备份文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(backups.items) { item in
                    Menu {
                        Button {
                            pendingRestore = item
                        } label: {
                            Label("恢复这份备份", systemImage: "arrow.uturn.backward")
                        }
                        Button {
                            Task { await share(item) }
                        } label: {
                            Label("分享 / 存到文件", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            pendingDelete = item
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        BackupRow(item: item)
                    }
                    .swipeActions {
                        Button(role: .destructive) { pendingDelete = item } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("备份文件")
            } footer: {
                Text("点一份备份可以恢复、分享或删除。自动备份最多保留最近 \(BackupCenter.autoKeep) 份，手动备份不会被自动删除。")
            }

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
                    Label("从文件导入", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("JSON 导出与导入")
            } footer: {
                Text("备份包含自定义班次、标签、循环、工时规则和每日记录，与网页版格式一致，可以互相导入。")
            }

            Section("状态") {
                // 从记下的第一天到今天；循环提前生成的未来日子不算
                LabeledContent("记录天数", value: "\(store.document.recordedDays(today: store.todayKey)) 天")
                LabeledContent("班次 / 标签",
                               value: "\(store.document.shifts.count) / \(store.document.tags.count)")
            }
        }
        .pageBackground()
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .task { await backups.reload() }
        .refreshable { await backups.reload() }
        .onChange(of: backups.useICloud) { _, _ in
            Task { await backups.reload() }
        }
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
        .sheet(item: $shareItem) { file in
            ShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
        }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil },
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
                guard let document = pendingImport else { return }
                Task { await apply(document) }
                pendingImport = nil
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        } message: {
            if let pendingImport {
                Text("这份备份包含 \(pendingImport.records.count) 天记录、\(pendingImport.shifts.count) 个班次。当前数据会先存一份「恢复前快照」。")
            }
        }
        .confirmationDialog("用这份备份覆盖当前全部数据？",
                            isPresented: Binding(get: { pendingRestore != nil },
                                                 set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible) {
            Button("恢复", role: .destructive) {
                guard let item = pendingRestore else { return }
                Task { await restore(item) }
                pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("当前数据会先存一份「恢复前快照」，恢复错了可以再恢复回来。")
        }
        .confirmationDialog("删除这份备份？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                guard let item = pendingDelete else { return }
                Task {
                    do { try await backups.delete(item) } catch { errorMessage = error.localizedDescription }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .onChange(of: store.document) { _, _ in
            // 数据变了，之前生成的导出文件就过期了
            exportURL = nil
        }
    }

    // MARK: - 文案

    private var lastAutoText: String {
        guard let date = backups.lastAutoAt else { return "还没有" }
        let where_ = backups.lastAutoLocation?.label ?? ""
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)) + " · " + where_
    }

    private var autoFooter: String {
        guard backups.autoEnabled else { return "关闭后不再自动备份，已有的备份文件保留。" }
        let period = backups.frequency == .daily ? "每天" : "每周"
        let place = backups.useICloud ? "iCloud 云盘（iCloud 用不了时存在本机）" : "本机"
        return "App 退到后台时自动备份到\(place)。\(period)一份，同一\(backups.frequency == .daily ? "天" : "周")里再备份会覆盖这一份；数据没变或为空时不备份。"
    }

    // MARK: - 动作

    private func backupNow() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let location = try await backups.backupNow(store.document)
            showToast("已备份到\(location.label)", symbol: location.symbol)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ item: BackupItem) async {
        do {
            let document = try await backups.document(in: item)
            await apply(document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 覆盖当前数据。覆盖前先存一份「恢复前快照」。
    private func apply(_ document: ScheduleDocument) async {
        await backups.saveSafetySnapshot(of: store.document)
        store.replaceDocument(document)
        exportURL = nil
        showToast("已恢复 \(document.records.count) 天记录")
    }

    private func share(_ item: BackupItem) async {
        guard let url = await backups.shareableURL(for: item) else {
            errorMessage = BackupStoreError.notDownloaded.localizedDescription
            return
        }
        shareItem = ShareFile(url: url)
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

private struct BackupRow: View {
    let item: BackupItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.location.symbol)
                .font(.body)
                .foregroundStyle(item.location == .iCloud ? Palette.blue : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text("\(item.kind.label) · \(item.location.label) · \(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct ShareFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// 系统分享面板。备份文件可以「存储到文件」、AirDrop 或发给自己。
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
