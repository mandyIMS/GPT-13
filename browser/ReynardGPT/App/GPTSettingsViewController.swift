import GeckoView
import UIKit

@MainActor
final class GPTSettingsViewController: UITableViewController {
    private let clearWebsiteData: () async throws -> Void
    private let didClearWebsiteData: () -> Void

    init(
        clearWebsiteData: @escaping () async throws -> Void,
        didClearWebsiteData: @escaping () -> Void
    ) {
        self.clearWebsiteData = clearWebsiteData
        self.didClearWebsiteData = didClearWebsiteData
        super.init(style: .insetGrouped)
        title = "GPT Settings"
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

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 2 : 1
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        section == 0 ? "Runtime" : "Website Data"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        if indexPath.section == 0, indexPath.row == 0 {
            cell.textLabel?.text = "Gecko"
            cell.detailTextLabel?.text = GeckoRuntime.version
        } else if indexPath.section == 0 {
            cell.textLabel?.text = "JIT"
            cell.detailTextLabel?.text = GPTJITController.shared.state.description
        } else {
            cell.textLabel?.text = "Clear GPT Sign-in Data"
            cell.textLabel?.textColor = .systemRed
            cell.detailTextLabel?.text = GPTWebsiteDataClearDiagnostics.summary
            cell.selectionStyle = .default
        }
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }

        let alert = UIAlertController(
            title: "Sign out and clear website data?",
            message: "This removes Muse, Google, Apple and Microsoft sign-in data stored inside Muse Web. It does not affect Safari or other apps.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await self.clearWebsiteData()
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
                    self.showResult(
                        title: "Ready to Reset GPT",
                        message: "Tap OK to close GPT, then reopen it. The Gecko profile will be removed before the browser engine starts."
                    ) { [weak self] in
                        guard let self else { return }
                        self.dismiss(animated: true) {
                            self.didClearWebsiteData()
                        }
                    }
                } catch {
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
                    self.showResult(title: "Unable to Clear Data", message: error.localizedDescription)
                }
            }
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
