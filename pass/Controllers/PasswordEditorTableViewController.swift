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
        case name, fields, body, delete
    }

    private enum FieldsRow {
        case field(Int), addPassword, addOneTimePassword, addText
    }

    var password: Password?

    /// The folder the entry is in, shown in front of its name but not part of what is typed.
    var folder = ""
    var name = ""
    private var fields: [Field] = []
    private var body = ""
    /// Entries can carry free-form text, like the key in an SSH entry; new ones are made of fields only.
    private var hasBody = false

    private var sections: [Section] {
        [.name, .fields] + (hasBody ? [.body] : []) + (password == nil ? [] : [.delete])
    }

    private var fieldsRows: [FieldsRow] {
        let canAddPassword = Defaults.storeFormat == .sec || !fields.contains { $0.key == Constants.PASSWORD_KEYWORD }
        return fields.indices.map(FieldsRow.field) + (canAddPassword ? [.addPassword] : []) + [.addOneTimePassword, .addText]
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
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self

        guard let password else {
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

    // MARK: - Table view data source

    override func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section] == .fields ? fieldsRows.count : 1
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section] == .fields && Defaults.storeFormat == .sec ? "FieldsExplanation.".localize() : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .name:
            let cell = tableView.dequeueReusableCell(withIdentifier: "nameCell", for: indexPath) as! NameTableViewCell
            cell.set(folder: folder, name: name)
            cell.onChange = { [weak self] in self?.name = $0 }
            return cell
        case .fields:
            return fieldsCell(for: indexPath)
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

    private func fieldsCell(for indexPath: IndexPath) -> UITableViewCell {
        switch fieldsRows[indexPath.row] {
        case let .field(index):
            let cell = tableView.dequeueReusableCell(withIdentifier: "fieldCell", for: indexPath) as! FieldTableViewCell
            cell.set(field: fields[index], allowsSecret: Defaults.storeFormat == .sec)
            cell.onChange = { [weak self, weak cell] field in
                guard let self, let cell, let row = tableView.indexPath(for: cell)?.row else {
                    return
                }
                fields[row] = field
            }
            return cell
        case .addPassword:
            return actionCell(for: indexPath, title: "AddPasswordField".localize(), image: "key")
        case .addOneTimePassword:
            return actionCell(for: indexPath, title: "AddOneTimePassword".localize(), image: "qrcode.viewfinder")
        case .addText:
            return actionCell(for: indexPath, title: "AddText".localize(), image: "text.alignleft")
        }
    }

    private func actionCell(for indexPath: IndexPath, title: String, image: String) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "default", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = title
        content.textProperties.color = .tintColor
        content.image = UIImage(systemName: image)
        cell.contentConfiguration = content
        return cell
    }

    // MARK: - Table view delegate

    override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard sections[indexPath.section] == .fields, case .field = fieldsRows[indexPath.row] else {
            return false
        }
        return true
    }

    override func tableView(_: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        tableView(tableView, canEditRowAt: indexPath)
    }

    override func tableView(_: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        fields.insert(fields.remove(at: source.row), at: destination.row)
    }

    /// Fields only move among themselves, above the buttons that add them.
    override func tableView(_: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
        guard proposed.section == source.section else {
            return proposed.section < source.section ? IndexPath(row: 0, section: source.section) : IndexPath(row: fields.count - 1, section: source.section)
        }
        return IndexPath(row: min(proposed.row, fields.count - 1), section: source.section)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, case let .field(index) = fieldsRows[indexPath.row] else {
            return
        }
        let rowsBefore = fieldsRows.count
        fields.remove(at: index)
        tableView.performBatchUpdates {
            tableView.deleteRows(at: [indexPath], with: .automatic)
            updateAddPasswordRow(rowsBefore: rowsBefore - 1, section: indexPath.section)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch sections[indexPath.section] {
        case .fields:
            switch fieldsRows[indexPath.row] {
            case .addPassword:
                let hasPassword = fields.contains { $0.key == Constants.PASSWORD_KEYWORD }
                addField(Field(key: hasPassword ? "" : Constants.PASSWORD_KEYWORD, value: Defaults.passwordGenerator.generate(), isSecret: true))
            case .addOneTimePassword:
                performSegue(withIdentifier: "showQRScannerSegue", sender: self)
            case .addText:
                addField(Field(key: "", value: ""))
            case .field:
                break
            }
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

    private func addField(_ field: Field) {
        guard let section = sections.firstIndex(of: .fields) else {
            return
        }
        let rowsBefore = fieldsRows.count
        fields.append(field)
        let indexPath = IndexPath(row: fields.count - 1, section: section)
        tableView.performBatchUpdates {
            tableView.insertRows(at: [indexPath], with: .automatic)
            updateAddPasswordRow(rowsBefore: rowsBefore + 1, section: section)
        }
        let cell = tableView.cellForRow(at: indexPath) as? FieldTableViewCell
        if field.key.isEmpty {
            cell?.keyTextField.becomeFirstResponder()
        } else if field.value.isEmpty {
            cell?.valueTextField.becomeFirstResponder()
        }
    }

    /// In the pass format, the password is the first line, so there is room for one only.
    private func updateAddPasswordRow(rowsBefore: Int, section: Int) {
        let row = IndexPath(row: fields.count, section: section)
        if fieldsRows.count < rowsBefore {
            tableView.deleteRows(at: [row], with: .automatic)
        } else if fieldsRows.count > rowsBefore {
            tableView.insertRows(at: [row], with: .automatic)
        }
    }

    private func insertScannedOTPField(_ otpauth: String) {
        if let index = fields.firstIndex(where: \.isOtpauth), let section = sections.firstIndex(of: .fields) {
            fields[index].value = otpauth
            tableView.reloadRows(at: [IndexPath(row: index, section: section)], with: .automatic)
        } else {
            addField(Field(key: Constants.OTP_KEYWORD, value: otpauth, isSecret: true))
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
        if segue.identifier == "showQRScannerSegue" {
            let navigationController = segue.destination as? UINavigationController
            (navigationController?.topViewController as? QRScannerController ?? segue.destination as? QRScannerController)?.delegate = self
        }
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

// MARK: - Reordering

extension PasswordEditorTableViewController: UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard self.tableView(tableView, canMoveRowAt: indexPath) else {
            return []
        }
        return [UIDragItem(itemProvider: NSItemProvider())]
    }

    func tableView(_: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath _: IndexPath?) -> UITableViewDropProposal {
        guard session.localDragSession != nil else {
            return UITableViewDropProposal(operation: .forbidden)
        }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_: UITableView, performDropWith _: UITableViewDropCoordinator) {}
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

        textField.placeholder = "Name".localize()
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.textContentType = .emailAddress
        textField.keyboardType = .emailAddress
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
