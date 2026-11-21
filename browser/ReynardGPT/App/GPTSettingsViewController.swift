import GeckoView
import UIKit

@MainActor
final class GPTSettingsViewController: UITableViewController {
    private let clearWebsiteData: () async throws -> Void
    private let didClearWebsiteData: () -> Void
    private let onSiteSelected: (URL) -> Void

    private var sites: [GPTSite] {
        return GPTSiteStore.allSites
    }

    init(
        clearWebsiteData: @escaping () async throws -> Void,
        didClearWebsiteData: @escaping () -> Void,
        onSiteSelected: @escaping (URL) -> Void
    ) {
        self.clearWebsiteData = clearWebsiteData
        self.didClearWebsiteData = didClearWebsiteData
        self.onSiteSelected = onSiteSelected
        super.init(style: .insetGrouped)
        title = "Muse Settings"
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
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return sites.count + 1
        case 1:
            return 2
        default:
            return 1
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch section {
        case 0:
            return "網站"
        case 1:
            return "Runtime"
        default:
            return "Website Data"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        if indexPath.section == 0 {
            if indexPath.row < sites.count {
                let site = sites[indexPath.row]
                cell.textLabel?.text = site.name
                if site.name != site.host {
                    cell.detailTextLabel?.text = site.host
                }
                cell.accessoryType = site == GPTSiteStore.selectedSite ? .checkmark : .none
                cell.selectionStyle = .default
            } else {
                cell.textLabel?.text = "自行加入網址…"
                cell.selectionStyle = .default
            }
        } else if indexPath.section == 1, indexPath.row == 0 {
            cell.textLabel?.text = "Gecko"
            cell.detailTextLabel?.text = GeckoRuntime.version
        } else if indexPath.section == 1 {
            cell.textLabel?.text = "JIT"
            cell.detailTextLabel?.text = GPTJITController.shared.state.description
        } else {
            cell.textLabel?.text = "Clear Muse Sign-in Data"
            cell.textLabel?.textColor = .systemRed
            cell.detailTextLabel?.text = GPTWebsiteDataClearDiagnostics.summary
            cell.selectionStyle = .default
        }
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            if indexPath.row < sites.count {
                let site = sites[indexPath.row]
                GPTSiteStore.select(site)
                onSiteSelected(site.url)
                dismiss(animated: true)
            } else {
                presentAddSiteAlert()
            }
            return
        }
        guard indexPath.section == 2 else { return }

        let alert = UIAlertController(
            title: "Sign out and clear website data?",
            message: "This removes sign-in data for all sites stored inside Muse Web 測試版 v3. It does not affect Safari or other apps.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await self.clearWebsiteData()
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .none)
                    self.showResult(
                        title: "Ready to Reset Muse Web 測試版 v3",
                        message: "Tap OK to close Muse Web 測試版 v3, then reopen it. The Gecko profile will be removed before the browser engine starts."
                    ) { [weak self] in
                        guard let self else { return }
                        self.dismiss(animated: true) {
                            self.didClearWebsiteData()
                        }
                    }
                } catch {
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .none)
                    self.showResult(title: "Unable to Clear Data", message: error.localizedDescription)
                }
            }
        })
        present(alert, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        canEditRowAt indexPath: IndexPath
    ) -> Bool {
        return indexPath.section == 0
            && indexPath.row < sites.count
            && GPTSiteStore.isCustomSite(sites[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete,
              indexPath.section == 0,
              indexPath.row < sites.count else {
            return
        }
        GPTSiteStore.removeCustomSite(sites[indexPath.row])
        tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
    }

    private func presentAddSiteAlert() {
        let alert = UIAlertController(
            title: "自行加入網址",
            message: "輸入網站網址，例如：example.com",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "example.com"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "加入", style: .default) { [weak self] _ in
            guard let self else { return }
            let input = alert.textFields?.first?.text ?? ""
            guard let site = GPTSiteStore.site(from: input) else {
                self.showResult(title: "網址看不懂", message: "請輸入網站網址，例如：example.com")
                return
            }
            if let existing = GPTSiteStore.existingSite(forHost: site.host) {
                GPTSiteStore.select(existing)
                self.onSiteSelected(existing.url)
                self.dismiss(animated: true)
                return
            }
            GPTSiteStore.addCustomSite(site)
            GPTSiteStore.select(site)
            self.onSiteSelected(site.url)
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func showResult(
        title: String,
        message: String,
        completion: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion?() })
        present(alert, animated: true)
    }

    @objc private func done() {
        dismiss(animated: true)
    }
}
