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
    /// Without a search, the entries for the code's site and the others; with one, a single list.
    private var sections = [[PasswordTableEntry]]()
    private let searchController = UISearchController(searchResultsController: nil)

    init(issuer: String, account: String) {
        self.issuer = issuer
        self.account = account
        // Like the AutoFill list, which this sheet is the counterpart of.
        super.init(style: .grouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AddVerificationCode".localize()
        // What the code is for, so it is clear where it is going.
        navigationItem.prompt = [issuer, account].filter { !$0.isEmpty }.joined(separator: " · ")
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
        updateShown()
    }

    func updateSearchResults(for _: UISearchController) {
        updateShown()
        tableView.reloadData()
    }

    private func updateShown() {
        let query = searchController.searchBar.text ?? ""
        let all = entries.ranked(by: query)
        let suggested = query.isEmpty && !issuer.isEmpty ? all.filter { $0.matchesSite(issuer) } : []
        sections = suggested.isEmpty ? [all] : [suggested, all.filter { !$0.matchesSite(issuer) }]
    }

    override func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard sections.count > 1 else {
            return nil
        }
        return (section == 0 ? "SuggestedPasswords" : "OtherPasswords").localize()
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let entry = sections[indexPath.section][indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = entry.title
        content.secondaryText = entry.categoryText.isEmpty ? nil : entry.categoryText
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        choose(.entry(path: sections[indexPath.section][indexPath.row].passwordEntity.path))
    }

    private func choose(_ choice: Choice) {
        searchController.isActive = false
        dismiss(animated: true) { [onChoose] in
            onChoose?(choice)
        }
    }
}
