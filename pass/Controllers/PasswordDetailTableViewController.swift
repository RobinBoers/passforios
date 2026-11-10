//
//  PasswordDetailTableViewController.swift
//  pass
//
//  Created by Mingshen Sun on 2/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import Gopenpgp
import passAutoFillExtension
import passKit
import UIKit

class PasswordDetailTableViewController: UITableViewController, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    var passwordEntity: PasswordEntity? {
        didSet {
            passwordPath = passwordEntity?.path
        }
    }

    var password: Password?
    private var oneTimePasswordIndexPath: IndexPath?
    private var shouldPopCurrentView = false
    private let passwordStore = PasswordStore.shared

    // preserve path so it can be reloaded even if the passwordEntity is deleted during the update process
    private var passwordPath: String?

    private lazy var editUIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(pressEdit))
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)

    private struct TableSection {
        var type: PasswordDetailTableViewControllerSectionType
        var header: String?
        var item: [LabelTableViewCellData] = []

        init(type: PasswordDetailTableViewControllerSectionType, header: String? = nil) {
            self.type = type
            self.header = header
        }
    }

    private var tableData = [TableSection]()

    private enum PasswordDetailTableViewControllerSectionType {
        case name, main, addition, misc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UINib(nibName: "LabelTableViewCell", bundle: nil), forCellReuseIdentifier: "labelCell")
        tableView.register(UINib(nibName: "PasswordDetailTitleTableViewCell", bundle: nil), forCellReuseIdentifier: "passwordDetailTitleTableViewCell")

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapMenu))
        tapGesture.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tapGesture)
        tapGesture.delegate = self
        tableView.addInteraction(editMenuInteraction)

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52

        editUIBarButtonItem.isEnabled = false
        navigationItem.rightBarButtonItem = editUIBarButtonItem
        navigationItem.largeTitleDisplayMode = .never

        decryptThenShowPassword()
        setupOneTimePasswordAutoRefresh()

        // pop the current view because this password might be "discarded"
        NotificationCenter.default.addObserver(self, selector: #selector(setShouldPopCurrentView), name: .passwordStoreChangeDiscarded, object: nil)

        // reset the data table if the disaply settings have been changed
        NotificationCenter.default.addObserver(self, selector: #selector(decryptThenShowPasswordSelector), name: .passwordDetailDisplaySettingChanged, object: nil)

        // A Siri shortcut can change the state of the app in the background. Hence, reload when opening the app.
        NotificationCenter.default.addObserver(self, selector: #selector(actOnPossiblePasswordStoreUpdate), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if shouldPopCurrentView {
            let alert = UIAlertController(title: "Notice".localize(), message: "PreviousChangesDiscarded.".localize(), preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction.okAndPopView(controller: self))
            present(alert, animated: true, completion: nil)
        }
    }

    @objc
    private func decryptThenShowPasswordSelector(_: Any) {
        decryptThenShowPassword()
    }

    private func decryptThenShowPassword() {
        decryptThenShowPasswordLocalKey()
    }

    private func decryptThenShowPasswordLocalKey(keyID: String? = nil) {
        guard let passwordEntity else {
            Utils.alert(title: "CannotShowPassword".localize(), message: "PasswordDoesNotExist".localize(), controller: self, completion: {
                self.navigationController!.popViewController(animated: true)
            })
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // decrypt password
            do {
                let requestPGPKeyPassphrase = Utils.createRequestPGPKeyPassphraseHandler(controller: self)
                self.password = try self.passwordStore.decrypt(passwordEntity: passwordEntity, keyID: keyID, requestPGPKeyPassphrase: requestPGPKeyPassphrase)
                self.showPassword()
            } catch let AppError.pgpPrivateKeyNotFound(keyID: key) {
                DispatchQueue.main.async {
                    // alert: cancel or try again
                    let alert = UIAlertController(title: "CannotShowPassword".localize(), message: AppError.pgpPrivateKeyNotFound(keyID: key).localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction.cancelAndPopView(controller: self))
                    let selectKey = UIAlertAction.selectKey(controller: self) { action in
                        self.decryptThenShowPasswordLocalKey(keyID: action.title)
                    }
                    alert.addAction(selectKey)

                    self.present(alert, animated: true, completion: nil)
                }
            } catch {
                DispatchQueue.main.async {
                    // alert: cancel or try again
                    let alert = UIAlertController(title: "CannotShowPassword".localize(), message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction.cancelAndPopView(controller: self))
                    alert.addAction(
                        UIAlertAction(title: "TryAgain".localize(), style: .default) { _ in
                            self.decryptThenShowPasswordLocalKey()
                        }
                    )
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }
    }

    private func showPassword() {
        DispatchQueue.main.async { [weak self] in
            self?.setTableData()
            self?.tableView.reloadData()
            self?.editUIBarButtonItem.isEnabled = true
        }
    }

    private func setupOneTimePasswordAutoRefresh() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // bail out of the timer code if the object has been freed
            guard let strongSelf = self,
                  let otpType = strongSelf.password?.otpType,
                  otpType != .none,
                  let indexPath = strongSelf.oneTimePasswordIndexPath,
                  let cell = strongSelf.tableView.cellForRow(at: indexPath) as? LabelTableViewCell else {
                return
            }
            switch otpType {
            case .totp:
                if let (title, otp) = strongSelf.password?.getOtpStrings() {
                    strongSelf.tableData[indexPath.section].item[indexPath.row] = LabelTableViewCellData(title: title, content: otp)
                    cell.cellData?.title = title
                    cell.cellData?.content = otp
                }
            default:
                break
            }
        }
    }

    @objc
    private func pressEdit(_: Any?) {
        performSegue(withIdentifier: "editPasswordSegue", sender: self)
    }

    @objc
    private func setShouldPopCurrentView() {
        shouldPopCurrentView = true
    }

    @IBAction
    private func cancelEditPassword(segue _: UIStoryboardSegue) {}

    @IBAction
    private func saveEditPassword(segue _: UIStoryboardSegue) {
        if password!.changed != 0 {
            saveEditPassword(password: password!)
        }
    }

    private func saveEditPassword(password: Password, keyID: String? = nil) {
        do {
            passwordEntity = try passwordStore.edit(passwordEntity: passwordEntity!, password: password, keyID: keyID)
            setTableData()
            tableView.reloadData()
            Feedback.success()
        } catch let AppError.pgpPublicKeyNotFound(keyID: key) {
            DispatchQueue.main.async {
                // alert: cancel or select keys
                let alert = UIAlertController(title: "Cannot Edit Password", message: AppError.pgpPublicKeyNotFound(keyID: key).localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction.cancelAndPopView(controller: self))
                let selectKey = UIAlertAction.selectKey(controller: self) { action in
                    self.saveEditPassword(password: password, keyID: action.title)
                }
                alert.addAction(selectKey)

                self.present(alert, animated: true, completion: nil)
            }
            return
        } catch {
            DispatchQueue.main.async {
                Utils.alert(title: "Error".localize(), message: error.localizedDescription, controller: self, completion: nil)
            }
        }
    }

    @IBAction
    private func deletePassword(segue _: UIStoryboardSegue) {
        do {
            try passwordStore.delete(passwordEntity: passwordEntity!)
        } catch {
            Utils.alert(title: "Error".localize(), message: error.localizedDescription, controller: self, completion: nil)
        }
        _ = navigationController?.popViewController(animated: true)
    }

    private func setTableData() {
        tableData = [TableSection]()
        oneTimePasswordIndexPath = nil
        let password = password!

        // name section
        var section = TableSection(type: .name)
        section.item.append(LabelTableViewCellData(title: "", content: ""))
        tableData.append(section)

        // main section
        section = TableSection(type: .main)
        if let user = password.user {
            section.item.append(LabelTableViewCellData(title: Constants.USER_KEYWORD, content: user))
        }
        if !password.password.isEmpty {
            let title = password.entry.isBodyPrimary ? Constants.BODY_KEYWORD : Constants.PASSWORD_KEYWORD
            section.item.append(LabelTableViewCellData(title: title, content: password.password, isSecret: true))
        }
        if !section.item.isEmpty {
            tableData.append(section)
        }

        // one time password
        if password.otpType != .none, let (title, otp) = password.getOtpStrings() {
            section = TableSection(type: .addition, header: "OneTimePassword".localize())
            section.item.append(LabelTableViewCellData(title: title, content: otp))
            tableData.append(section)
            oneTimePasswordIndexPath = IndexPath(row: 0, section: tableData.count - 1)
        }

        // other fields
        let fields = password.additionalFields
        if !fields.isEmpty {
            section = TableSection(type: .addition, header: "Fields".localize())
            section.item = fields.map { LabelTableViewCellData(title: $0.key, content: $0.value, isSecret: $0.isSecret) }
            tableData.append(section)
        }

        // notes
        if let notes = password.notes {
            section = TableSection(type: .addition, header: "Notes".localize())
            section.item.append(LabelTableViewCellData(title: "", content: notes))
            tableData.append(section)
        }

        // misc section
        section = TableSection(type: .misc)
        section.item.append(LabelTableViewCellData(title: "ShowRaw".localize(), content: ""))
        tableData.append(section)
    }

    override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
        if segue.identifier == "editPasswordSegue" {
            if let controller = segue.destination as? UINavigationController {
                if let editController = controller.viewControllers.first as? EditPasswordTableViewController {
                    editController.password = password
                }
            }
        } else if segue.identifier == "showRawPasswordSegue" {
            if let controller = segue.destination as? UINavigationController {
                if let controller = controller.viewControllers.first as? RawPasswordViewController {
                    controller.password = password
                }
            }
        }
    }

    @objc
    private func tapMenu(recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }
        let tapLocation = recognizer.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: tapLocation), tableView.cellForRow(at: indexPath) is LabelTableViewCell else {
            return
        }
        editMenuInteraction.presentEditMenu(with: UIEditMenuConfiguration(identifier: indexPath as NSIndexPath, sourcePoint: tapLocation))
    }

    func editMenuInteraction(_: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions _: [UIMenuElement]) -> UIMenu? {
        guard let indexPath = configuration.identifier as? IndexPath, let cell = tableView.cellForRow(at: indexPath) as? LabelTableViewCell else {
            return nil
        }
        return UIMenu(children: cell.menuActions())
    }

    func editMenuInteraction(_: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        guard let indexPath = configuration.identifier as? IndexPath, let cell = tableView.cellForRow(at: indexPath) as? LabelTableViewCell else {
            return .null
        }
        return cell.contentLabel.convert(cell.contentLabel.bounds, to: tableView)
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view!.isKind(of: UIButton.classForCoder()) {
            return false
        }
        return true
    }

    @IBAction
    private func back(segue _: UIStoryboardSegue) {}

    func getNextHOTP() {
        guard password != nil, passwordEntity != nil, password?.otpType == .hotp else {
            DispatchQueue.main.async {
                Utils.alert(title: "Error".localize(), message: "GetNextPasswordOfNonHotp.".localize(), controller: self, completion: nil)
            }
            return
        }

        // copy HOTP to pasteboard (will update counter)
        if let plainPassword = password!.getNextHotp() {
            SecurePasteboard.shared.copy(textToCopy: plainPassword)
        }

        // commit the change of HOTP counter
        if password!.changed != 0 {
            do {
                passwordEntity = try passwordStore.edit(passwordEntity: passwordEntity!, password: password!)
                Feedback.success()
            } catch {
                Utils.alert(title: "Error".localize(), message: error.localizedDescription, controller: self)
            }
        }
    }

    func openLink(to address: String?) {
        guard address != nil, let url = URL(string: formActualWebAddress(from: address!)) else {
            DispatchQueue.main.async {
                Utils.alert(title: "Error".localize(), message: "CannotFindValidUrl".localize(), controller: self, completion: nil)
            }
            return
        }
        SecurePasteboard.shared.copy(textToCopy: password?.password)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func formActualWebAddress(from: String) -> String {
        let lowercased = from.lowercased()
        if !(lowercased.starts(with: "https://") || lowercased.starts(with: "http://")) {
            return "https://\(from)"
        }
        return from
    }

    override func numberOfSections(in _: UITableView) -> Int {
        tableData.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableData[section].item.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionIndex = indexPath.section
        let rowIndex = indexPath.row
        let tableDataItem = tableData[sectionIndex].item[rowIndex]
        switch tableData[sectionIndex].type {
        case .name:
            let cell = tableView.dequeueReusableCell(withIdentifier: "passwordDetailTitleTableViewCell", for: indexPath) as! PasswordDetailTitleTableViewCell
            cell.passwordImageImageView.image = nil
            cell.passwordImageImageView.isHidden = true
            cell.labelImageConstraint.isActive = false
            cell.labelCellConstraint.isActive = true
            let passwordName = passwordEntity!.name
            if passwordEntity!.isSynced == false {
                cell.nameLabel.text = "\(passwordName) ↻"
            } else {
                cell.nameLabel.text = passwordName
            }
            cell.categoryLabel.text = passwordEntity!.dirText
            cell.selectionStyle = .none
            return cell
        case .addition, .main:
            let cell = tableView.dequeueReusableCell(withIdentifier: "labelCell", for: indexPath) as! LabelTableViewCell
            cell.delegatePasswordTableView = self
            cell.cellData = tableDataItem
            cell.selectionStyle = .none
            return cell
        case .misc:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = tableDataItem.title
            cell.selectionStyle = .default
            return cell
        }
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        tableData[section].header
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == tableData.count - 1, let password else {
            return nil
        }
        return "LastUpdated".localize(passwordStore.getLatestUpdateInfo(path: password.path))
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = tableData[indexPath.section]
        if section.type == .misc {
            if section.item[indexPath.row].title == "ShowRaw".localize() {
                performSegue(withIdentifier: "showRawPasswordSegue", sender: self)
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension PasswordDetailTableViewController {
    @objc
    func actOnPossiblePasswordStoreUpdate() {
        DispatchQueue.main.async {
            if let path = self.passwordPath {
                // reload PasswordEntity because all PasswordEntities are re-created on PasswordStore update
                self.passwordEntity = PasswordStore.shared.fetchPasswordEntity(with: path)

                // dismiss if the PasswordEntity does not exist anymore
                if self.passwordEntity == nil {
                    self.navigationController?.popToRootViewController(animated: true)
                } else {
                    self.decryptThenShowPassword()
                }
            }
        }
    }
}
