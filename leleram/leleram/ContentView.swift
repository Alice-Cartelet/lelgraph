import SwiftUI
import UniformTypeIdentifiers
import WebKit
import CryptoKit
import AVKit

struct PageElement: Codable {
    var text: String?
    var imageBase64: String?
    var videoFileName: String?
    var isGIF: Bool? = false
}

struct FileNameEncryptor {
    private static let keyString = allkeystring
    static let key: SymmetricKey = {
        let keyData = Data(keyString.utf8)
        let padded = keyData + Data(repeating: 0, count: max(0, 32 - keyData.count))
        return SymmetricKey(data: padded.prefix(32))
    }()

    static func encryptToFileName(_ plain: String) -> String? {
        guard let data = plain.data(using: .utf8) else { return nil }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return nil }
            var b64 = combined.base64EncodedString()
            b64 = b64.replacingOccurrences(of: "+", with: "-")
            b64 = b64.replacingOccurrences(of: "/", with: "_")
            b64 = b64.replacingOccurrences(of: "=", with: "")
            return b64
        } catch {
            print("encryptToFileName error: \(error)")
            return nil
        }
    }

    static func decryptFileName(_ encoded: String) -> String? {
        var b64 = encoded
        b64 = b64.replacingOccurrences(of: "-", with: "+")
        b64 = b64.replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder > 0 {
            b64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let combined = Data(base64Encoded: b64) else { return nil }
        do {
            let sealed = try AES.GCM.SealedBox(combined: combined)
            let decrypted = try AES.GCM.open(sealed, using: key)
            return String(data: decrypted, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

struct CryptoHelper {
    static let key: SymmetricKey = {
        let keyString = allkeystring
        let keyData = keyString.data(using: .utf8) ?? Data()
        let keyBytes = keyData.prefix(16)
        return SymmetricKey(data: keyBytes)
    }()

    // MARK: - Data 加密/解密
    static func encrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined!
    }
    
    static func decrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    // MARK: - String 加密/解密
    static func encryptString(_ string: String) throws -> String {
        let data = string.data(using: .utf8)!
        let encryptedData = try encrypt(data)
        return encryptedData.base64EncodedString()
    }
    
    static func decryptString(_ base64: String) throws -> String {
        guard let data = Data(base64Encoded: base64) else { return "" }
        let decryptedData = try decrypt(data)
        return String(data: decryptedData, encoding: .utf8) ?? ""
    }
}

enum SortOption: String, CaseIterable, Identifiable {
    case name = "文件名"
    case date = "修改日期"
    var id: String { self.rawValue }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case ascending = "升序"
    case descending = "降序"
    var id: String { self.rawValue }
}

struct ContentView: View {
    @State private var deletedMode = false
    @State private var files: [URL] = []
    @State private var deletedFiles: [URL] = []
    @State private var showAliceImporter = false
    @State private var searchText = ""
    @State private var sortOption: SortOption = .name
    @State private var sortOrder: SortOrder = .ascending

    let baseURL: URL
    let deletedDir: URL

    init() {
        let fileDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baseURL = fileDir
        self.deletedDir = fileDir.appendingPathComponent("Deleted")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: deletedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: baseURL.appendingPathComponent("Videos"), withIntermediateDirectories: true)
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredFiles, id: \.self) { file in
                    let encryptedName = file.deletingPathExtension().lastPathComponent
                    let displayName = displayNameForEncrypted(encryptedName)
                    NavigationLink(destination: ViewerView(fileURL: file, baseURL: baseURL, fileName: displayName)) {
                        Text(displayName)
                    }
                    .contextMenu {
                        Button("重命名") {
                            rename(file)
                        }
                        Button("分享") {
                            shareFile(file)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let file = filteredFiles[index]
                        if deletedMode {
                            try? FileManager.default.removeItem(at: file)
                        } else {
                            let dest = deletedDir.appendingPathComponent(file.lastPathComponent)
                            try? FileManager.default.moveItem(at: file, to: dest)
                        }
                    }
                    loadFiles()
                }
            }
            .searchable(text: $searchText)
            .navigationTitle(deletedMode ? "已删除" : "文件目录")
            .fileImporter(
                isPresented: $showAliceImporter,
                allowedContentTypes: [UTType(filenameExtension: "alice") ?? .data],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    importAliceFiles(from: urls)
                case .failure(let error):
                    print("导入失败: \(error)")
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !deletedMode {
                        Button(action: {
                            showAddNewFileAlert()
                        }) {
                            Image(systemName: "plus")
                        }

                        Button(action: {
                            showAliceImporter = true
                        }) {
                            Image(systemName: "square.and.arrow.down.on.square")
                        }
                    }

                    Button(action: {
                        deletedMode.toggle()
                        loadFiles()
                    }) {
                        Image(systemName: deletedMode ? "arrow.uturn.left" : "trash")
                    }

                    Menu {
                        Picker("排序依据", selection: $sortOption) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        Picker("排序顺序", selection: $sortOrder) {
                            ForEach(SortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .onAppear {
                loadFiles()
            }
        }
    }

    var filteredFiles: [URL] {
        let target = deletedMode ? deletedFiles : files
        let filtered = searchText.isEmpty ? target : target.filter {
            let enc = $0.deletingPathExtension().lastPathComponent
            if let originalName = FileNameEncryptor.decryptFileName(enc) {
                return originalName.localizedCaseInsensitiveContains(searchText)
            } else {
                return $0.lastPathComponent.localizedCaseInsensitiveContains(searchText)
            }
        }
        return filtered.sorted(by: { lhs, rhs in
            switch sortOption {
            case .name:
                let lhsName = FileNameEncryptor.decryptFileName(lhs.deletingPathExtension().lastPathComponent) ?? lhs.deletingPathExtension().lastPathComponent
                let rhsName = FileNameEncryptor.decryptFileName(rhs.deletingPathExtension().lastPathComponent) ?? rhs.deletingPathExtension().lastPathComponent
                let result = lhsName.localizedCaseInsensitiveCompare(rhsName)
                return sortOrder == .ascending ? (result == .orderedAscending) : (result == .orderedDescending)
            case .date:
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return sortOrder == .ascending ? lhsDate < rhsDate : lhsDate > rhsDate
            }
        })
    }

    func loadFiles() {
        files = (try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil))?.filter {
            !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "alice" && !$0.path.contains("Deleted")
        } ?? []

        deletedFiles = (try? FileManager.default.contentsOfDirectory(at: deletedDir, includingPropertiesForKeys: nil))?.filter {
            $0.pathExtension == "alice"
        } ?? []
    }

    func importAliceFiles(from urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            let originalName = url.deletingPathExtension().lastPathComponent
            let finalEncryptedName: String
            if FileNameEncryptor.decryptFileName(originalName) != nil {
                finalEncryptedName = originalName
            } else {
                finalEncryptedName = FileNameEncryptor.encryptToFileName(originalName) ?? originalName
            }

            let destURL = baseURL.appendingPathComponent(finalEncryptedName + ".alice")
            guard !FileManager.default.fileExists(atPath: destURL.path) else { continue }

            do {
                try FileManager.default.copyItem(at: url, to: destURL)
            } catch {
                print("导入 .alice 文件失败: \(error)")
            }
        }
        loadFiles()
    }

    func rename(_ file: URL) {
        let encryptedName = file.deletingPathExtension().lastPathComponent
        let originalName = FileNameEncryptor.decryptFileName(encryptedName) ?? String(encryptedName.prefix(8)) + "..."
        let alert = UIAlertController(title: "重命名", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = originalName
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            let newName = alert.textFields?.first?.text ?? ""
            guard !newName.isEmpty else { return }
            guard let newEncryptedName = FileNameEncryptor.encryptToFileName(newName) else { return }
            let newURL = file.deletingLastPathComponent().appendingPathComponent(newEncryptedName + ".alice")
            do {
                try FileManager.default.moveItem(at: file, to: newURL)
                loadFiles()
            } catch {
                print("重命名失败", error)
            }
        })
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }

    func showAddNewFileAlert() {
        let alert = UIAlertController(title: "输入文件名", message: nil, preferredStyle: .alert)
        alert.addTextField()
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            let name = alert.textFields?.first?.text ?? ""
            guard !name.isEmpty else { return }
            guard let encryptedName = FileNameEncryptor.encryptToFileName(name) else { return }
            let newFile = baseURL.appendingPathComponent(encryptedName + ".alice")
            let emptyContent: [PageElement] = []
            if let jsonData = try? JSONEncoder().encode(emptyContent),
               let encryptedData = try? CryptoFileEncryptor.encrypt(jsonData) {
                do {
                    try encryptedData.write(to: newFile)
                    loadFiles()
                } catch {
                    print("保存文件失败", error)
                }
            }
        })
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }

    func displayNameForEncrypted(_ encryptedName: String) -> String {
        if let original = FileNameEncryptor.decryptFileName(encryptedName) {
            return original
        } else {
            return String(encryptedName.prefix(8)) + "..."
        }
    }

    func shareFile(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let activityVC = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

struct CryptoFileEncryptor {
    private static let fileKey = FileNameEncryptor.key

    static func encrypt(_ plain: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plain, using: fileKey)
        guard let combined = sealed.combined else {
            throw NSError(domain: "CryptoFileEncryptor", code: -1, userInfo: [NSLocalizedDescriptionKey: "failed to seal"])
        }
        return combined
    }

    static func decrypt(_ combined: Data) throws -> Data {
        let sealed = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealed, using: fileKey)
    }
}
