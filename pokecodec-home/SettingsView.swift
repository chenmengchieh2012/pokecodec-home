
import SwiftUI
import SwiftData

/// 設定頁面：管理 GitHub Token 與 Gist ID
struct SettingsView: View {
    @ObservedObject var settings: SecureSettings
    var unsyncedHistories: [TeamHistory]
    var onReset: () -> Void
    var onReupload: (TeamHistory) -> Void
    @State private var showingResetAlert = false
    @State private var isEditingGistId = false
    @State private var tempGistId = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("GitHub 設定")) {
                    SecureField("Personal Access Token", text: $settings.githubToken)
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Gist ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                if isEditingGistId {
                                    // Save
                                    settings.gistId = tempGistId
                                } else {
                                    // Start editing
                                    tempGistId = settings.gistId
                                }
                                isEditingGistId.toggle()
                            }) {
                                Text(isEditingGistId ? "儲存" : "編輯")
                                    .font(.caption)
                                    .foregroundColor(isEditingGistId ? .green : .blue)
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        if isEditingGistId {
                            TextField("輸入 Gist ID", text: $tempGistId)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disableAutocorrection(true)
                                .autocapitalization(.none)
                        } else {
                            HStack {
                                Text(settings.gistId.isEmpty ? "尚未產生" : settings.gistId)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(settings.gistId.isEmpty ? .secondary : .primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                if !settings.gistId.isEmpty {
                                    Button(action: {
                                        UIPasteboard.general.string = settings.gistId
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    
                    if !settings.gistId.isEmpty && !isEditingGistId {
                        Button("清除 Gist ID (重新產生)") {
                            settings.gistId = ""
                        }
                        .foregroundColor(.red)
                    }
                }
                
                if !unsyncedHistories.isEmpty && !settings.gistId.isEmpty {
                    Section(header: Text("未同步版本")) {
                        ForEach(unsyncedHistories) { history in
                            Button {
                                onReupload(history)
                            } label: {
                                HStack {
                                    Text("v\(history.lockId)")
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Text(formatDate(history.timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Image(systemName: "icloud.and.arrow.up")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section(footer: Text("Token 需要 Gist 權限以進行雲端備份。")) {
                    Link("取得 GitHub Token", destination: URL(string: "https://github.com/settings/tokens")!)
                }
                
                Section(header: Text("危險區域")) {
                    Button(role: .destructive, action: { showingResetAlert = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("重置所有資料")
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("確定要重置嗎？", isPresented: $showingResetAlert) {
                Button("取消", role: .cancel) { }
                Button("刪除", role: .destructive) { 
                    onReset()
                    dismiss()
                }
            } message: {
                Text("此動作將刪除所有寶可夢與綁定裝置，且無法復原。")
            }
        }
    }
    
    private func formatDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
