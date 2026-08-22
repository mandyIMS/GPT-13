import Foundation
import GeckoView

extension Notification.Name {
    static let gptDownloadsDidChange = Notification.Name("GPTDownloadsDidChange")
}

struct GPTDownloadItem: Equatable {
    enum State: Equatable {
        case downloading
        case completed
    }

    let id: UUID
    let fileName: String
    let fileURL: URL?
    let mimeType: String?
    let addedAt: Date
    let downloadedBytes: Int64
    let expectedBytes: Int64?
    let state: State

    var progress: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(max(Double(downloadedBytes) / Double(expectedBytes), 0), 1)
    }
}

struct GPTDownloadSummary: Equatable {
    let items: [GPTDownloadItem]
    let activeCount: Int
    let hasUnviewedCompletedDownloads: Bool
}

@MainActor
final class GPTDownloadStore {
    static let shared = GPTDownloadStore()

    private struct Record: Codable {
        let id: UUID
        let fileName: String
        let relativePath: String
        let sourceURL: String
        let mimeType: String?
        let fileSize: Int64
        let addedAt: Date
    }

    private struct ActiveDownload {
        let id: UUID
        let localFilePath: String
        let fileName: String
        let destinationURL: URL
        let sourceURL: String
        let mimeType: String?
        let addedAt: Date
        let expectedBytes: Int64?
        var downloadedBytes: Int64
    }

    private let fileManager = FileManager.default
    private let downloadsDirectory: URL
    private let manifestURL: URL
    private var records: [Record] = []
    private var activeDownloads: [String: ActiveDownload] = [:]
    private var hasUnviewedCompletedDownloads = false
    private var lastProgressNotification = Date.distantPast

    private init() {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
              ).first else {
            fatalError("GPT download storage directories are unavailable")
        }

        downloadsDirectory = documents.appendingPathComponent("Downloads", isDirectory: true)
        let metadataDirectory = applicationSupport
            .appendingPathComponent("ReynardGPT", isDirectory: true)
        manifestURL = metadataDirectory.appendingPathComponent("Downloads.json")

        try? fileManager.createDirectory(
            at: downloadsDirectory,
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: metadataDirectory,
            withIntermediateDirectories: true
        )
        loadRecords()
    }

    func summary() -> GPTDownloadSummary {
        let activeItems = activeDownloads.values.map { download in
            GPTDownloadItem(
                id: download.id,
                fileName: download.fileName,
                fileURL: nil,
                mimeType: download.mimeType,
                addedAt: download.addedAt,
                downloadedBytes: download.downloadedBytes,
                expectedBytes: download.expectedBytes,
                state: .downloading
            )
        }
        let completedItems = records.compactMap { record -> GPTDownloadItem? in
            let fileURL = downloadsDirectory.appendingPathComponent(record.relativePath)
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
            return GPTDownloadItem(
                id: record.id,
                fileName: record.fileName,
                fileURL: fileURL,
                mimeType: record.mimeType,
                addedAt: record.addedAt,
                downloadedBytes: record.fileSize,
                expectedBytes: record.fileSize,
                state: .completed
            )
        }
        return GPTDownloadSummary(
            items: (activeItems + completedItems).sorted { $0.addedAt > $1.addedAt },
            activeCount: activeItems.count,
            hasUnviewedCompletedDownloads: hasUnviewedCompletedDownloads
        )
    }

    @discardableResult
    func begin(_ response: ExternalResponseInfo) -> Bool {
        if activeDownloads[response.localFilePath] != nil { return true }

        let fileName = uniqueFileName(
            suggestedName: response.filename,
            sourceURL: URL(string: response.url),
            mimeType: response.mimeType
        )
        let destinationURL = downloadsDirectory.appendingPathComponent(fileName)
        activeDownloads[response.localFilePath] = ActiveDownload(
            id: UUID(),
            localFilePath: response.localFilePath,
            fileName: fileName,
            destinationURL: destinationURL,
            sourceURL: response.url,
            mimeType: response.mimeType,
            addedAt: Date(),
            expectedBytes: response.contentLength,
            downloadedBytes: 0
        )
        notifyChange()
        return true
    }

    func update(localFilePath: String, bytesReceived: Int64) -> Bool {
        guard var active = activeDownloads[localFilePath] else { return false }
        active.downloadedBytes = max(0, bytesReceived)
        activeDownloads[localFilePath] = active

        let now = Date()
        if now.timeIntervalSince(lastProgressNotification) >= 0.1 {
            lastProgressNotification = now
            notifyChange()
        }
        return true
    }

    func complete(localFilePath: String, succeeded: Bool) {
        guard let active = activeDownloads.removeValue(forKey: localFilePath) else {
            try? fileManager.removeItem(at: URL(fileURLWithPath: localFilePath))
            return
        }

        let temporaryURL = URL(fileURLWithPath: localFilePath)
        guard succeeded, importFile(from: temporaryURL, to: active.destinationURL) else {
            try? fileManager.removeItem(at: temporaryURL)
            notifyChange()
            return
        }

        let fileSize = ((try? fileManager.attributesOfItem(atPath: active.destinationURL.path)[.size])
            as? NSNumber)?.int64Value ?? active.downloadedBytes
        records.insert(
            Record(
                id: active.id,
                fileName: active.fileName,
                relativePath: active.destinationURL.lastPathComponent,
                sourceURL: active.sourceURL,
                mimeType: active.mimeType,
                fileSize: fileSize,
                addedAt: active.addedAt
            ),
            at: 0
        )
        hasUnviewedCompletedDownloads = true
        saveRecords()
        notifyChange()
    }

    func markCompletedAsViewed() {
        guard hasUnviewedCompletedDownloads else { return }
        hasUnviewedCompletedDownloads = false
        notifyChange()
    }

    func remove(id: UUID) {
        if let active = activeDownloads.first(where: { $0.value.id == id }) {
            activeDownloads.removeValue(forKey: active.key)
            try? fileManager.removeItem(at: URL(fileURLWithPath: active.key))
            notifyChange()
            return
        }

        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records.remove(at: index)
        let fileURL = downloadsDirectory.appendingPathComponent(record.relativePath)
        try? fileManager.removeItem(at: fileURL)
        saveRecords()
        notifyChange()
    }

    func removeAllCompleted() {
        for record in records {
            let fileURL = downloadsDirectory.appendingPathComponent(record.relativePath)
            try? fileManager.removeItem(at: fileURL)
        }
        records.removeAll()
        hasUnviewedCompletedDownloads = false
        saveRecords()
        notifyChange()
    }

    private func loadRecords() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([Record].self, from: data) else {
            records = []
            return
        }
        records = decoded.filter { record in
            fileManager.fileExists(
                atPath: downloadsDirectory.appendingPathComponent(record.relativePath).path
            )
        }
        if records.count != decoded.count { saveRecords() }
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func importFile(from sourceURL: URL, to destinationURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return false }
        do {
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                try? fileManager.removeItem(at: sourceURL)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            return false
        }
    }

    private func uniqueFileName(
        suggestedName: String?,
        sourceURL: URL?,
        mimeType: String?
    ) -> String {
        let candidate = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = sourceURL?.lastPathComponent
        var name = sanitizedFileName(candidate?.isEmpty == false ? candidate! : fallback)
        if name.isEmpty { name = "Download" }
        if (name as NSString).pathExtension.isEmpty, let extensionName = fileExtension(for: mimeType) {
            name += ".\(extensionName)"
        }

        let base = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension
        var result = name
        var index = 2
        while fileManager.fileExists(atPath: downloadsDirectory.appendingPathComponent(result).path)
            || activeDownloads.values.contains(where: { $0.fileName == result }) {
            let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
            result = "\(base) (\(index))\(suffix)"
            index += 1
        }
        return result
    }

    private func sanitizedFileName(_ value: String?) -> String {
        guard let value else { return "" }
        let lastComponent = (value as NSString).lastPathComponent
        let forbidden = CharacterSet(charactersIn: "/\\:\0")
            .union(.controlCharacters)
        return lastComponent.unicodeScalars
            .map { forbidden.contains($0) ? "_" : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fileExtension(for mimeType: String?) -> String? {
        switch mimeType?.lowercased().split(separator: ";").first.map(String.init) {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "image/webp": return "webp"
        case "image/gif": return "gif"
        case "application/pdf": return "pdf"
        case "application/zip": return "zip"
        case "text/plain": return "txt"
        default: return nil
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .gptDownloadsDidChange, object: self)
    }
}
