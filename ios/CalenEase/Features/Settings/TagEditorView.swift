import SwiftUI

/// 职责标签编辑。标签和班次相互独立，一天可以挂多个。
struct TagEditorView: View {
    let tag: DutyTag?

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var draft = DutyTag(id: "", name: "", shortName: "", color: AccentHex.purple)
    @State private var loaded = false

    private var isNew: Bool { tag == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("标签名称", text: $draft.name)
                    TextField("简称（日历上显示）", text: $draft.shortName)
                        .onChange(of: draft.shortName) { _, value in
                            if value.count > 6 { draft.shortName = String(value.prefix(6)) }
                        }
                }
                Section("颜色") {
                    ColorPaletteRow(palette: AccentHex.tagPalette, selection: $draft.color)
                }
                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            if let tag { store.deleteTag(tag) }
                            showToast("标签已删除", symbol: "trash")
                            dismiss()
                        } label: {
                            Label("删除这个标签", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    } footer: {
                        Text("删除后，已挂这个标签的日子会自动去掉它，排班本身不受影响。")
                    }
                }
            }
            .pageBackground()
            .navigationTitle(isNew ? "新增标签" : "编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var next = draft
                        next.name = next.name.trimmingCharacters(in: .whitespaces)
                        if next.shortName.trimmingCharacters(in: .whitespaces).isEmpty {
                            next.shortName = String(next.name.prefix(3))
                        }
                        store.saveTag(next)
                        showToast(isNew ? "已新增标签" : "已保存")
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let tag {
                    draft = tag
                } else {
                    let used = Set(store.document.tags.map(\.color))
                    draft = DutyTag(id: ShiftCatalog.makeId("tag"),
                                    name: "",
                                    shortName: "",
                                    color: AccentHex.tagPalette.first { !used.contains($0) } ?? AccentHex.purple)
                }
            }
        }
    }
}
