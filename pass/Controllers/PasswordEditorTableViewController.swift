//
//  PasswordEditorTableViewController.swift
//  pass
//
//  Created by Mingshen Sun on 12/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import OneTimePassword
import passKit
import UIKit

class PasswordEditorTableViewController: UITableViewController {
    private enum Section {
        case name, fields, actions, body, delete
    }

    private enum Action {
        case addText, addPassword, scanQRCode
    }

    var password: Password?
    /// What a new entry starts from, like one of `sec`'s protos.
    var template: Entry?

    /// The folder the entry is in, shown in front of its name but not part of what is typed.
    var folder = ""
    var name = "" {
        didSet {
            updateSaveButton()
        }
    }

    private var fields: [Field] = [] {
        didSet {
            updateSaveButton()
        }
    }

    private var body = "" {
        didSet {
            updateSaveButton()
        }
    }

    /// Entries can carry free-form text, like the key in an SSH entry; new ones are made of fields only.
    private var hasBody = false
    /// The entry as it was, to tell whether there is anything to lose when the sheet is swiped away.
    private var original: (namePath: String, plainText: String)?

    private var hasChanges: Bool {
        original.map { $0.namePath != namePath || $0.plainText != entry.plainText } ?? false
    }

    private var sections: [Section] {
        [.name] + (fields.isEmpty ? [] : [.fields]) + [.actions] + (hasBody ? [.body] : []) + (password == nil ? [] : [.delete])
    }

    /// In the pass format, the password is the first line, so there is room for one only.
    private var actions: [Action] {
        let canAddPassword = Defaults.storeFormat == .sec || !fields.contains { $0.key == Constants.PASSWORD_KEYWORD }
        return [.addText] + (canAddPassword ? [.addPassword] : []) + [.scanQRCode]
    }

    var entry: Entry {
        Entry(fields: fields.filter { !$0.key.isEmpty || !$0.value.isEmpty }, body: body.trimmingCharacters(in: .newlines))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(NameTableViewCell.self, forCellReuseIdentifier: "nameCell")
        tableView.register(FieldTableViewCell.self, forCellReuseIdentifier: "fieldCell")
        tableView.register(UINib(nibName: "TextViewTableViewCell", bundle: nil), forCellReuseIdentifier: "textViewCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "default")
        tableView.keyboardDismissMode = .interactive
        tableView.sectionFooterHeight = UITableView.automaticDimension
        // Always editing, like a contact card: fields delete and move by their controls, and the add rows insert.
        tableView.allowsSelectionDuringEditing = true
        setEditing(true, animated: false)
        if #available(iOS 26.0, *) {
            navigationItem.rightBarButtonItem?.style = .prominent
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [unowned self] _ in
            if hasChanges {
                confirmDiscard()
            } else {
                dismiss(animated: true)
            }
        })

        guard let password else {
            if let template {
                // Like Add Password does, a password to keep, or to replace.
                fields = template.fields.map { field in
                    guard field.key == Constants.PASSWORD_KEYWORD, field.value.isEmpty else {
                        return field
                    }
                    return Field(key: field.key, value: Defaults.passwordGenerator.generate(), isSecret: true)
                }
                body = template.body
                hasBody = template.isBodyPrimary || !body.isEmpty
            }
            return
        }
        let path = password.namePath
        if let slash = path.lastIndex(of: "/") {
            folder = String(path[...slash])
            name = String(path[path.index(after: slash)...])
        } else {
            name = path
        }
        fields = password.entry.fields
        body = password.entry.body
        hasBody = !body.isEmpty
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if original == nil {
            original = (namePath, entry.plainText)
            updateSaveButton()
        }
        navigationController?.presentationController?.delegate = self
    }

    // MARK: - Table view data source

    override func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .fields:
            return fields.count
        case .actions:
            return actions.count
        case .body, .delete, .name:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .name:
            let cell = tableView.dequeueReusableCell(withIdentifier: "nameCell", for: indexPath) as! NameTableViewCell
            cell.set(folder: folder, name: name)
            cell.onChange = { [weak self] in self?.name = $0 }
            return cell
        case .fields:
            let cell = tableView.dequeueReusableCell(withIdentifier: "fieldCell", for: indexPath) as! FieldTableViewCell
            cell.set(field: fields[indexPath.row], allowsSecret: Defaults.storeFormat == .sec)
            cell.onChange = { [weak self, weak cell] field in
                guard let self, let cell, let row = tableView.indexPath(for: cell)?.row else {
                    return
                }
                fields[row] = field
            }
            return cell
        case .actions:
            switch actions[indexPath.row] {
            case .addText:
                return actionCell(for: indexPath, title: "AddText".localize())
            case .addPassword:
                return actionCell(for: indexPath, title: "AddPasswordField".localize())
            case .scanQRCode:
                return actionCell(for: indexPath, title: "ScanQRCode".localize())
            }
        case .body:
            let cell = tableView.dequeueReusableCell(withIdentifier: "textViewCell", for: indexPath) as! TextViewTableViewCell
            cell.setContent(content: body)
            cell.contentTextView.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
            cell.contentTextView.delegate = self
            return cell
        case .delete:
            let cell = tableView.dequeueReusableCell(withIdentifier: "default", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "DeletePassword".localize()
            content.textProperties.color = .systemRed
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            return cell
        }
    }

    private func actionCell(for indexPath: IndexPath, title: String) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "default", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = title
        cell.contentConfiguration = content
        return cell
    }

    // MARK: - Table view delegate

    override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        [.fields, .actions].contains(sections[indexPath.section])
    }

    override func tableView(_: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        switch sections[indexPath.section] {
        case .fields:
            return .delete
        case .actions:
            return .insert
        default:
            return .none
        }
    }

    override func tableView(_: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        [.fields, .actions].contains(sections[indexPath.section])
    }

    override func tableView(_: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        sections[indexPath.section] == .fields
    }

    override func tableView(_: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        fields.insert(fields.remove(at: source.row), at: destination.row)
    }

    /// Fields only move among themselves.
    override func tableView(_: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
        guard proposed.section == source.section else {
            return proposed.section < source.section ? IndexPath(row: 0, section: source.section) : IndexPath(row: fields.count - 1, section: source.section)
        }
        return proposed
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else {
            perform(actions[indexPath.row])
            return
        }
        let actionsBefore = actions
        let actionsSectionBefore = sections.firstIndex(of: .actions)
        fields.remove(at: indexPath.row)
        tableView.performBatchUpdates {
            if fields.isEmpty {
                tableView.deleteSections([indexPath.section], with: .automatic)
            } else {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
            updateActions(from: actionsBefore, section: actionsSectionBefore)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch sections[indexPath.section] {
        case .actions:
            perform(actions[indexPath.row])
        case .delete:
            let alert = UIAlertController(title: "DeletePassword?".localize(), message: nil, preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(title: "Delete".localize(), style: .destructive) { [unowned self] _ in
                    performSegue(withIdentifier: "deletePasswordSegue", sender: self)
                }
            )
            alert.addAction(UIAlertAction.cancel())
            present(alert, animated: true, completion: nil)
        default:
            break
        }
    }

    private func perform(_ action: Action) {
        switch action {
        case .addText:
            addField(Field(key: "", value: ""))
        case .addPassword:
            let hasPassword = fields.contains { $0.key == Constants.PASSWORD_KEYWORD }
            addField(Field(key: hasPassword ? "" : Constants.PASSWORD_KEYWORD, value: Defaults.passwordGenerator.generate(), isSecret: true))
        case .scanQRCode:
            scanQRCode()
        }
    }

    /// Saving needs a name, and for an entry that exists, something to save.
    private func updateSaveButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !name.trimmed.isEmpty && (password == nil || hasChanges)
    }

    /// The fields form a group once there is one; without any, an empty group would leave a gap.
    private func addField(_ field: Field) {
        let actionsBefore = actions
        let actionsSectionBefore = sections.firstIndex(of: .actions)
        let isFirst = fields.isEmpty
        fields.append(field)
        guard let section = sections.firstIndex(of: .fields) else {
            return
        }
        let indexPath = IndexPath(row: fields.count - 1, section: section)
        tableView.performBatchUpdates {
            if isFirst {
                tableView.insertSections([section], with: .automatic)
            } else {
                tableView.insertRows(at: [indexPath], with: .automatic)
            }
            updateActions(from: actionsBefore, section: actionsSectionBefore)
        }
        let cell = tableView.cellForRow(at: indexPath) as? FieldTableViewCell
        if field.key.isEmpty {
            cell?.keyTextField.becomeFirstResponder()
        } else if field.value.isEmpty {
            cell?.valueTextField.becomeFirstResponder()
        }
    }

    /// Within a batch update, rows are deleted by where they were and inserted by where they go.
    private func updateActions(from before: [Action], section sectionBefore: Int?) {
        guard let sectionBefore, let section = sections.firstIndex(of: .actions), before != actions else {
            return
        }
        if actions.count < before.count {
            tableView.deleteRows(at: [IndexPath(row: 1, section: sectionBefore)], with: .automatic)
        } else {
            tableView.insertRows(at: [IndexPath(row: 1, section: section)], with: .automatic)
        }
    }

    private func insertScannedOTPField(_ otpauth: String) {
        if let index = fields.firstIndex(where: \.isOtpauth), let section = sections.firstIndex(of: .fields) {
            fields[index].value = otpauth
            tableView.reloadRows(at: [IndexPath(row: index, section: section)], with: .automatic)
        } else {
            addField(Field.oneTimeCode(otpauth))
        }
    }

    /// In a sheet of its own, so swiping it away leaves the entry being edited.
    private func scanQRCode() {
        let scanner = QRScannerController()
        scanner.delegate = self
        scanner.title = "ScanQRCode".localize()
        scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak scanner] _ in
            scanner?.dismiss(animated: true)
        })
        present(UINavigationController(rootViewController: scanner), animated: true)
    }

    // MARK: - Validation

    private var namePath: String {
        folder + name.trimmed
    }

    func getNamePath() -> (String, String) {
        guard let encodedName = namePath.stringByAddingPercentEncodingForRFC3986(), let url = URL(string: encodedName) else {
            return ("", "")
        }
        let name = url.lastPathComponent
        let path = url.appendingPathExtension("gpg").path
        return (name, path)
    }

    func validate() -> Bool {
        view.endEditing(true)
        return checkName() && checkFields()
    }

    private func checkFields() -> Bool {
        let invalid = entry.fields.first { field in
            !field.value.isEmpty && (!Field.isValid(key: field.key) || field.value.contains(where: \.isNewline))
        }
        let passwords = entry.fields.filter { $0.key == Constants.PASSWORD_KEYWORD }.count
        guard invalid == nil, passwords <= 1 else {
            Utils.alert(title: "CannotSave".localize(), message: "InvalidField.".localize(invalid?.key ?? Constants.PASSWORD_KEYWORD), controller: self, completion: nil)
            return false
        }
        return true
    }

    private func checkName() -> Bool {
        let namePath = namePath
        guard !name.trimmed.isEmpty else {
            Utils.alert(title: "CannotSave".localize(), message: "FillInName.".localize(), controller: self, completion: nil)
            return false
        }

        guard !namePath.hasPrefix("/") else {
            Utils.alert(title: "CannotSave".localize(), message: "RemovePrefix.".localize(), controller: self, completion: nil)
            return false
        }

        guard let path = namePath.stringByAddingPercentEncodingForRFC3986(), var passwordURL = URL(string: path) else {
            Utils.alert(title: "CannotSave".localize(), message: "PasswordNameInvalid.".localize(), controller: self, completion: nil)
            return false
        }

        // check whether we can parse the filename (be consistent with PasswordStore::addPasswordEntities)
        var previousPathLength = Int.max
        while passwordURL.path != "." {
            passwordURL = passwordURL.deletingLastPathComponent()
            if passwordURL.path != ".", passwordURL.path.count >= previousPathLength {
                Utils.alert(title: "CannotSave".localize(), message: "CannotParseFilename.".localize(), controller: self, completion: nil)
                return false
            }
            previousPathLength = passwordURL.path.count
        }

        return true
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension PasswordEditorTableViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerShouldDismiss(_: UIPresentationController) -> Bool {
        !hasChanges
    }

    func presentationControllerDidAttemptToDismiss(_: UIPresentationController) {
        confirmDiscard()
    }

    func confirmDiscard() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "DiscardChanges".localize(), style: .destructive) { [weak self] _ in
            self?.navigationController?.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: "KeepEditing".localize(), style: .cancel))
        alert.popoverPresentationController?.sourceItem = navigationItem.leftBarButtonItem
        present(alert, animated: true)
    }
}

// MARK: - QRScannerControllerDelegate

extension PasswordEditorTableViewController: QRScannerControllerDelegate {
    func checkScannedOutput(line: String) -> (accepted: Bool, message: String) {
        if let url = URL(string: line), Token(url: url) != nil {
            return (true, "ValidTokenUrl".localize())
        }
        return (false, "InvalidTokenUrl".localize())
    }

    func handleScannedOutput(line: String) {
        insertScannedOTPField(line)
    }
}

// MARK: - UITextViewDelegate

extension PasswordEditorTableViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        body = textView.text
        // Grow the cell with its content.
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }
}

/// The entry's name, after its folder, which is shown but cannot be edited here.
private final class NameTableViewCell: UITableViewCell {
    private let textField = UITextField()
    private let folderLabel = UILabel()

    var onChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        folderLabel.font = .preferredFont(forTextStyle: .body)
        folderLabel.adjustsFontForContentSizeCategory = true
        folderLabel.textColor = .secondaryLabel
        folderLabel.setContentHuggingPriority(.required, for: .horizontal)
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        folderLabel.lineBreakMode = .byTruncatingHead

        textField.placeholder = "EntryName".localize()
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.clearButtonMode = .whileEditing
        textField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)

        let stack = UIStackView(arrangedSubviews: [folderLabel, textField])
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(folder: String, name: String) {
        folderLabel.text = folder
        folderLabel.isHidden = folder.isEmpty
        textField.text = name
    }

    @objc
    private func nameChanged() {
        onChange?(textField.text ?? "")
    }
}
