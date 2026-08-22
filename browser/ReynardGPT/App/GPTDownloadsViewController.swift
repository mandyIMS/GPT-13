import UIKit

@MainActor
final class GPTDownloadsViewController: UITableViewController {
    private let store: GPTDownloadStore
    private var items: [GPTDownloadItem] = []
    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "暂无下载"
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        return label
    }()

    init(store: GPTDownloadStore = .shared) {
        self.store = store
        super.init(style: .insetGrouped)
        title = "下载"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(done)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .trash,
            target: self,
            action: #selector(clearCompleted)
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadsDidChange),
            name: .gptDownloadsDidChange,
            object: store
        )
        reloadDownloads()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        store.markCompletedAsViewed()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = item.fileName
        cell.textLabel?.lineBreakMode = .byTruncatingMiddle
        cell.imageView?.image = UIImage(systemName: iconName(for: item))
        cell.imageView?.tintColor = .label

        switch item.state {
        case .downloading:
            let progressText = item.progress.map { "\(Int($0 * 100))%" } ?? "下载中"
            cell.detailTextLabel?.text = "\(progressText) · \(byteCount(item.downloadedBytes))"
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
            cell.selectionStyle = .none
        case .completed:
            cell.detailTextLabel?.text = "\(byteCount(item.downloadedBytes)) · \(dateText(item.addedAt))"
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        guard item.state == .completed, let fileURL = item.fileURL else { return }

        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(activity, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = items[indexPath.row]
        let title = item.state == .downloading ? "取消" : "删除"
        let action = UIContextualAction(style: .destructive, title: title) { [weak self] _, _, finish in
            self?.store.remove(id: item.id)
            finish(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func downloadsDidChange() {
        reloadDownloads()
    }

    private func reloadDownloads() {
        let summary = store.summary()
        items = summary.items
        tableView.backgroundView = items.isEmpty ? emptyLabel : nil
        navigationItem.leftBarButtonItem?.isEnabled = items.contains { $0.state == .completed }
        tableView.reloadData()
    }

    @objc private func clearCompleted() {
        let alert = UIAlertController(
            title: "删除所有已完成的下载？",
            message: "文件会从 GPT 的下载目录中永久删除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.store.removeAllCompleted()
        })
        present(alert, animated: true)
    }

    @objc private func done() {
        dismiss(animated: true)
    }

    private func iconName(for item: GPTDownloadItem) -> String {
        guard let mimeType = item.mimeType?.lowercased() else { return "doc" }
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        if mimeType.contains("zip") || mimeType.contains("archive") { return "archivebox" }
        return "doc"
    }

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
