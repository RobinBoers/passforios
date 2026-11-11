//
//  OneTimeCodeSetupController.swift
//  pass
//

import passKit
import UIKit

/// Asks where the verification code of an `otpauth` link goes: into a new entry, or one that exists.
final class OneTimeCodeSetupController: UITableViewController, UISearchResultsUpdating {
    enum Choice {
        case newEntry
        case entry(path: String)
    }

    var onChoose: ((Choice) -> Void)?

    private let issuer: String
    private let entries = PasswordStore.shared.fetchPasswordEntityCoreData(withDir: false).map(PasswordTableEntry.init)
    private var shown = [PasswordTableEntry]()
    private let searchController = UISearchController(searchResultsController: nil)

    init(issuer: String) {
        self.issuer = issuer
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SetUpCode".localize()
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [unowned self] _ in
            dismiss(animated: true)
        })
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        // Starts out narrowed to the site the code is for, when there are entries for it.
        if !issuer.isEmpty, entries.contains(where: { $0.matches(issuer) }) {
            searchController.searchBar.text = issuer
        }
        updateShown()
    }

    func updateSearchResults(for _: UISearchController) {
        updateShown()
        tableView.reloadData()
    }

    private func updateShown() {
        let query = searchController.searchBar.text ?? ""
        shown = entries
            .filter { query.isEmpty || $0.matches(query) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    override func numberOfSections(in _: UITableView) -> Int {
        2
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : shown.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        if indexPath.section == 0 {
            content.text = "NewPassword".localize()
            content.image = UIImage(systemName: "plus.circle.fill")
            content.textProperties.color = .tintColor
        } else {
            let entry = shown[indexPath.row]
            content.text = entry.title
            content.secondaryText = entry.categoryText.isEmpty ? nil : entry.categoryText
            content.secondaryTextProperties.color = .secondaryLabel
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 && !shown.isEmpty ? "AddToEntry".localize() : nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let choice = indexPath.section == 0 ? Choice.newEntry : .entry(path: shown[indexPath.row].passwordEntity.path)
        searchController.isActive = false
        dismiss(animated: true) { [onChoose] in
            onChoose?(choice)
        }
    }
}
