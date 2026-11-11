//
//  OneTimeCodeSetupController.swift
//  pass
//

import passKit
import UIKit

/// Asks which entry the verification code of an `otpauth` link goes into, or, with +, makes a new one.
final class OneTimeCodeSetupController: UITableViewController, UISearchResultsUpdating {
    enum Choice {
        case newEntry
        case entry(path: String)
    }

    var onChoose: ((Choice) -> Void)?

    private let issuer: String
    private let account: String
    private let entries = PasswordStore.shared.fetchPasswordEntityCoreData(withDir: false).map(PasswordTableEntry.init)
    private var shown = [PasswordTableEntry]()
    private let searchController = UISearchController(searchResultsController: nil)

    init(issuer: String, account: String) {
        self.issuer = issuer
        self.account = account
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AddVerificationCode".localize()
        // What the code is for, so it is clear where it is going.
        let code = [issuer, account].filter { !$0.isEmpty }.joined(separator: " · ")
        if #available(iOS 26.0, *) {
            navigationItem.subtitle = code
        } else {
            navigationItem.prompt = code
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [unowned self] _ in
            dismiss(animated: true)
        })
        let add = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [unowned self] _ in
            choose(.newEntry)
        })
        add.accessibilityLabel = "CreateNewEntry".localize()
        navigationItem.rightBarButtonItem = add
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
        shown = entries.ranked(by: query)
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        shown.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let entry = shown[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = entry.title
        content.secondaryText = entry.categoryText.isEmpty ? nil : entry.categoryText
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        choose(.entry(path: shown[indexPath.row].passwordEntity.path))
    }

    private func choose(_ choice: Choice) {
        searchController.isActive = false
        dismiss(animated: true) { [onChoose] in
            onChoose?(choice)
        }
    }
}
