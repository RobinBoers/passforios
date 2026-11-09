//
//  PasswordEditorTableViewController.swift
//  pass
//
//  Created by Mingshen Sun on 12/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import OneTimePassword
import passKit
import SafariServices
import UIKit

protocol PasswordSettingSliderTableViewCellDelegate: AnyObject {
    func generateAndCopyPassword()
}

class PasswordEditorTableViewController: UITableViewController {
    private enum Section {
        case name, password, fields, body, delete
    }

    private enum FieldsRow {
        case field(Int), addField, addOneTimePassword
    }

    var password: Password?

    var name = ""
    private var secretField = Field(key: Constants.PASSWORD_KEYWORD, value: "", isSecret: true)
    private var secretFieldIndex = 0
    private var fields: [Field] = []
    private var body = ""

    private var showsGeneratorSettings = false
    private var passwordGenerator: PasswordGenerator = Defaults.passwordGenerator

    private var sections: [Section] {
        password == nil ? [.name, .password, .fields, .body] : [.name, .password, .fields, .body, .delete]
    }

    private var fillPasswordCell: FillPasswordTableViewCell? {
        guard let section = sections.firstIndex(of: .password) else {
            return nil
        }
        return tableView.cellForRow(at: IndexPath(row: 0, section: section)) as? FillPasswordTableViewCell
    }

    /// The entry as edited, with the password at its original position among the fields.
    var entry: Entry {
        var fields = fields.filter { !$0.key.isEmpty || !$0.value.isEmpty }
        fields.insert(secretField, at: min(secretFieldIndex, fields.count))
        return Entry(fields: fields, body: body.trimmingCharacters(in: .newlines))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UINib(nibName: "TextFieldTableViewCell", bundle: nil), forCellReuseIdentifier: "textFieldCell")
        tableView.register(UINib(nibName: "TextViewTableViewCell", bundle: nil), forCellReuseIdentifier: "textViewCell")
        tableView.register(UINib(nibName: "FillPasswordTableViewCell", bundle: nil), forCellReuseIdentifier: "fillPasswordCell")
        tableView.register(UINib(nibName: "SliderTableViewCell", bundle: nil), forCellReuseIdentifier: "sliderCell")
        tableView.register(FieldTableViewCell.self, forCellReuseIdentifier: "fieldCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "default")
        tableView.keyboardDismissMode = .interactive

        guard let password else {
            return
        }
        name = password.namePath
        fields = password.entry.fields
        body = password.entry.body
        if let index = fields.firstIndex(where: { $0.key == Constants.PASSWORD_KEYWORD }) {
            secretField = fields.remove(at: index)
            secretFieldIndex = index
        } else {
            secretFieldIndex = fields.count
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Defaults.passwordGenerator = passwordGenerator
    }

    // MARK: - Table view data source

    private func fieldsRow(at row: Int) -> FieldsRow {
        switch row - fields.count {
        case 0:
            return .addField
        case 1:
            return .addOneTimePassword
        default:
            return .field(row)
        }
    }

    override func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .password:
            return showsGeneratorSettings ? 2 : 1
        case .fields:
            return fields.count + 2
        case .body, .delete, .name:
            return 1
        }
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .name:
            return "Name".localize()
        case .password:
            return "Password".localize()
        case .fields:
            return "Fields".localize()
        case .body:
            return "Notes".localize()
        case .delete:
            return nil
        }
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section] == .fields ? "FieldsExplanation.".localize() : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .name:
            let cell = tableView.dequeueReusableCell(withIdentifier: "textFieldCell", for: indexPath) as! TextFieldTableViewCell
            cell.setContent(content: name)
            cell.contentTextField.delegate = self
            cell.contentTextField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
            return cell
        case .password where indexPath.row == 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "fillPasswordCell", for: indexPath) as! FillPasswordTableViewCell
            cell.delegate = self
            cell.setContent(content: secretField.value)
            cell.contentTextField.delegate = self
            cell.contentTextField.addTarget(self, action: #selector(passwordChanged), for: .editingChanged)
            return cell
        case .password:
            return (tableView.dequeueReusableCell(withIdentifier: "sliderCell", for: indexPath) as! SliderTableViewCell)
                .set(title: "Length".localize())
                .configureSlider(with: PasswordGenerator.lengthLimits)
                .set(initialValue: passwordGenerator.limitedLength)
                .checkNewValue { $0 != self.passwordGenerator.length }
                .updateNewValue { self.passwordGenerator.length = $0 }
                .delegate(to: self)
        case .fields:
            return fieldsCell(for: indexPath)
        case .body:
            let cell = tableView.dequeueReusableCell(withIdentifier: "textViewCell", for: indexPath) as! TextViewTableViewCell
            cell.setContent(content: body)
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
        switch fieldsRow(at: indexPath.row) {
        case let .field(index):
            let cell = tableView.dequeueReusableCell(withIdentifier: "fieldCell", for: indexPath) as! FieldTableViewCell
            cell.set(field: fields[index])
            cell.onChange = { [weak self, weak cell] field in
                guard let self, let cell, let row = tableView.indexPath(for: cell)?.row else {
                    return
                }
                fields[row] = field
            }
            return cell
        case .addField:
            return actionCell(for: indexPath, title: "AddField".localize(), image: "plus.circle.fill")
        case .addOneTimePassword:
            return actionCell(for: indexPath, title: "AddOneTimePassword".localize(), image: "qrcode.viewfinder")
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
        guard sections[indexPath.section] == .fields, case .field = fieldsRow(at: indexPath.row) else {
            return false
        }
        return true
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, case let .field(index) = fieldsRow(at: indexPath.row) else {
            return
        }
        fields.remove(at: index)
        if index < secretFieldIndex {
            secretFieldIndex -= 1
        }
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch sections[indexPath.section] {
        case .fields:
            switch fieldsRow(at: indexPath.row) {
            case .addField:
                addField()
            case .addOneTimePassword:
                performSegue(withIdentifier: "showQRScannerSegue", sender: self)
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

    private func addField(_ field: Field = Field(key: "", value: "")) {
        guard let section = sections.firstIndex(of: .fields) else {
            return
        }
        fields.append(field)
        let indexPath = IndexPath(row: fields.count - 1, section: section)
        tableView.insertRows(at: [indexPath], with: .automatic)
        if field.key.isEmpty {
            (tableView.cellForRow(at: indexPath) as? FieldTableViewCell)?.keyTextField.becomeFirstResponder()
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

    // MARK: - Actions

    @objc
    private func nameChanged(_ sender: UITextField) {
        name = sender.text ?? ""
    }

    @objc
    private func passwordChanged(_ sender: UITextField) {
        secretField.value = sender.attributedText?.string ?? ""
    }

    private func setPassword(_ plainPassword: String) {
        secretField.value = plainPassword
        fillPasswordCell?.setContent(content: plainPassword)
    }

    private func showPasswordSettings() {
        if !showsGeneratorSettings {
            showHidePasswordSettings()
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
        if segue.identifier == "showQRScannerSegue" {
            let navigationController = segue.destination as? UINavigationController
            (navigationController?.topViewController as? QRScannerController ?? segue.destination as? QRScannerController)?.delegate = self
        }
    }

    // MARK: - Validation

    func getNamePath() -> (String, String) {
        guard let encodedName = name.stringByAddingPercentEncodingForRFC3986(), let url = URL(string: encodedName) else {
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
        let duplicatePassword = fields.contains { $0.key == Constants.PASSWORD_KEYWORD && !$0.value.isEmpty }
        guard invalid == nil, !duplicatePassword else {
            Utils.alert(title: "CannotSave".localize(), message: "InvalidField.".localize(invalid?.key ?? Constants.PASSWORD_KEYWORD), controller: self, completion: nil)
            return false
        }
        return true
    }

    private func checkName() -> Bool {
        // the name field should not be empty
        guard !name.isEmpty else {
            Utils.alert(title: "CannotSave".localize(), message: "FillInName.".localize(), controller: self, completion: nil)
            return false
        }

        // the name should not start with /
        guard name.hasPrefix("/") == false else {
            Utils.alert(title: "CannotSave".localize(), message: "RemovePrefix.".localize(), controller: self, completion: nil)
            return false
        }

        // the name field should be a valid url
        guard let path = name.stringByAddingPercentEncodingForRFC3986(),
              var passwordURL = URL(string: path) else {
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

// MARK: - FillPasswordTableViewCellDelegate

extension PasswordEditorTableViewController: FillPasswordTableViewCellDelegate {
    func generateAndCopyPassword() {
        showPasswordSettings()
        setPassword(passwordGenerator.generate())
    }

    func showHidePasswordSettings() {
        guard let section = sections.firstIndex(of: .password) else {
            return
        }
        showsGeneratorSettings.toggle()
        let indexPaths = [IndexPath(row: 1, section: section)]
        if showsGeneratorSettings {
            tableView.insertRows(at: indexPaths, with: .fade)
        } else {
            tableView.deleteRows(at: indexPaths, with: .fade)
        }
    }
}

// MARK: - PasswordSettingSliderTableViewCellDelegate

extension PasswordEditorTableViewController: PasswordSettingSliderTableViewCellDelegate {}

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

// MARK: - SFSafariViewControllerDelegate

extension PasswordEditorTableViewController: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_: SFSafariViewController) {
        let copiedLinesSplit = UIPasteboard.general.string?.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        if copiedLinesSplit?.count ?? 0 > 0 {
            let generatedPassword = copiedLinesSplit![0]
            let alert = UIAlertController(title: "WannaUseIt?".localize(), message: "", preferredStyle: UIAlertController.Style.alert)
            let message = NSMutableAttributedString(string: "\("SeemsLikeYouHaveCopiedSomething.".localize()) \("FirstStringIs:".localize())\n")
            message.append(Utils.attributedPassword(plainPassword: generatedPassword))
            alert.setValue(message, forKey: "attributedMessage")
            alert.addAction(
                UIAlertAction(title: "Yes", style: UIAlertAction.Style.default) { [unowned self] _ in
                    setPassword(generatedPassword)
                }
            )
            alert.addAction(UIAlertAction.cancel())
            present(alert, animated: true, completion: nil)
        }
    }
}

// MARK: - UITextFieldDelegate

extension PasswordEditorTableViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField == fillPasswordCell?.contentTextField {
            showPasswordSettings()
        }
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
