//
//  PasswordDetailTableViewController.swift
//  pass
//
//  Created by Mingshen Sun on 2/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import passKit
import SwiftUI
import UIKit

class PasswordDetailTableViewController: UITableViewController, UIEditMenuInteractionDelegate {
    var passwordEntity: PasswordEntity? {
        didSet {
            passwordPath = passwordEntity?.path
        }
    }

    var password: Password?
    private var oneTimePasswordIndexPath: IndexPath?
    private var revealed: IndexPath?
    private var oneTimePasswordTimer: Timer?
    private var shouldPopCurrentView = false
    private let passwordStore = PasswordStore.shared

    // preserve path so it can be reloaded even if the passwordEntity is deleted during the update process
    private var passwordPath: String?

    private lazy var editUIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(pressEdit))
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)

    private enum RowKind {
        case header, field, secret, link, oneTimePassword, notes, raw
    }

    private struct Row {
        var kind: RowKind
        var key = ""
        var value = ""
    }

    private struct TableSection {
        var header: String?
        var rows: [Row]
    }

    private var tableData = [TableSection]()

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.removeTopSpace()
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "header")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.addInteraction(editMenuInteraction)

        editUIBarButtonItem.isEnabled = false
        navigationItem.rightBarButtonItem = editUIBarButtonItem
        navigationItem.largeTitleDisplayMode = .never

        decryptThenShowPassword()

        // pop the current view because this password might be "discarded"
        NotificationCenter.default.addObserver(self, selector: #selector(setShouldPopCurrentView), name: .passwordStoreChangeDiscarded, object: nil)

        // reset the data table if the disaply settings have been changed
        NotificationCenter.default.addObserver(self, selector: #selector(decryptThenShowPasswordSelector), name: .passwordDetailDisplaySettingChanged, object: nil)

        // A Siri shortcut can change the state of the app in the background. Hence, reload when opening the app.
        NotificationCenter.default.addObserver(self, selector: #selector(actOnPossiblePasswordStoreUpdate), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
        // On whole seconds, as codes change on them, and in the common mode so that they tick while scrolling.
        let timer = Timer(fire: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.up)), interval: 1, repeats: true) { [weak self] _ in
            self?.updateOneTimePassword()
        }
        RunLoop.main.add(timer, forMode: .common)
        oneTimePasswordTimer = timer
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if shouldPopCurrentView {
            let alert = UIAlertController(title: "Notice".localize(), message: "PreviousChangesDiscarded.".localize(), preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction.okAndPopView(controller: self))
            present(alert, animated: true, completion: nil)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        oneTimePasswordTimer?.invalidate()
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
            } catch is CancellationError {
                DispatchQueue.main.async {
                    self.navigationController?.popViewController(animated: true)
                }
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
            self?.reloadTableData()
            self?.editUIBarButtonItem.isEnabled = true
        }
    }

    private func updateOneTimePassword() {
        guard password?.otpType == .totp, let indexPath = oneTimePasswordIndexPath, let otp = password?.currentOtp else {
            return
        }
        tableData[indexPath.section].rows[indexPath.row].value = otp
        if let cell = tableView.cellForRow(at: indexPath) {
            configure(cell, at: indexPath)
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
            reloadTableData()
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

    private func reloadTableData() {
        setTableData()
        revealed = nil
        tableView.reloadData()
        updateTitle()
    }

    private func setTableData() {
        let password = password!
        tableData = [TableSection(rows: [Row(kind: .header)])]
        oneTimePasswordIndexPath = nil

        var main = [Row]()
        if let user = password.user {
            main.append(Row(kind: .field, key: Constants.USER_KEYWORD, value: user))
        }
        if !password.password.isEmpty {
            main.append(Row(kind: .secret, key: password.entry.isBodyPrimary ? Constants.BODY_KEYWORD : Constants.PASSWORD_KEYWORD, value: password.password))
        }
        if password.otpType != .none, let otp = password.currentOtp {
            oneTimePasswordIndexPath = IndexPath(row: main.count, section: tableData.count)
            main.append(Row(kind: .oneTimePassword, key: password.entry.fields.first(where: \.isOtpauth)?.key ?? Constants.OTP_KEYWORD, value: otp))
        }
        if !main.isEmpty {
            tableData.append(TableSection(rows: main))
        }

        let fields = password.additionalFields.map { field in
            if field.isSecret {
                return Row(kind: .secret, key: field.key, value: field.value)
            }
            let isLink = field.key.lowercased().contains("url") || field.value.hasPrefix("https://") || field.value.hasPrefix("http://")
            return Row(kind: isLink ? .link : .field, key: field.key, value: field.value)
        }
        if !fields.isEmpty {
            tableData.append(TableSection(rows: fields))
        }

        if let notes = password.notes {
            tableData.append(TableSection(header: "Notes".localize(), rows: [Row(kind: .notes, value: notes)]))
        }

        tableData.append(TableSection(rows: [Row(kind: .raw, key: "ShowRaw".localize())]))
    }

    /// Shows the name in the navigation bar once the header no longer does.
    private func updateTitle() {
        guard tableData.first?.rows.first?.kind == .header else {
            return
        }
        let header = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
        let title = header.maxY - 32 > tableView.contentOffset.y + tableView.adjustedContentInset.top ? nil : passwordEntity?.name
        if navigationItem.title != title {
            navigationItem.title = title
        }
    }

    override func scrollViewDidScroll(_: UIScrollView) {
        updateTitle()
    }

    override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
        if segue.identifier == "editPasswordSegue" {
            if let controller = segue.destination as? UINavigationController {
                if let editController = controller.viewControllers.first as? EditPasswordTableViewController {
                    editController.password = password
                }
            }
        } else if segue.identifier == "showRawPasswordSegue", let controller = segue.destination as? RawPasswordViewController {
            controller.password = password
        }
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
                reloadTableData()
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
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func formActualWebAddress(from: String) -> String {
        let lowercased = from.lowercased()
        if !(lowercased.starts(with: "https://") || lowercased.starts(with: "http://")) {
            return "https://\(from)"
        }
        return from
    }

    // MARK: - Rows

    /// Shows at most one secret, for as long as its menu is up.
    private func reveal(_ indexPath: IndexPath?) {
        guard revealed != indexPath else {
            return
        }
        let changed = [revealed, indexPath].compactMap(\.self)
        revealed = indexPath
        // Reconfiguring waits for the menu to finish animating away; the cells change right away instead.
        for indexPath in changed {
            if let cell = tableView.cellForRow(at: indexPath) {
                configure(cell, at: indexPath)
            }
        }
        tableView.performBatchUpdates(nil)
    }

    private func configure(_ cell: UITableViewCell, at indexPath: IndexPath) {
        let row = tableData[indexPath.section].rows[indexPath.row]
        let countdown = cell.accessoryView as? CountdownView
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.key
        content.textProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.textProperties.color = .secondaryLabel
        content.secondaryText = row.value
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.color = .label
        content.textToSecondaryTextVerticalPadding = 3
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.accessibilityLabel = nil
        cell.accessibilityValue = nil

        switch row.kind {
        case .secret:
            content.secondaryTextProperties.font = Globals.passwordFont
            if revealed != indexPath {
                content.secondaryText = Globals.passwordDots
                cell.accessibilityLabel = row.key
            } else if !row.value.contains("\n") {
                let password = NSMutableAttributedString(attributedString: Utils.attributedPassword(plainPassword: row.value))
                password.addAttribute(.font, value: Globals.passwordFont, range: NSRange(location: 0, length: password.length))
                content.secondaryAttributedText = password
            }
        case .link:
            content.secondaryTextProperties.color = .tintColor
        case .oneTimePassword:
            content.secondaryText = Self.grouped(row.value)
            content.secondaryTextProperties.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .monospacedDigitSystemFont(ofSize: 20, weight: .medium))
            content.secondaryTextProperties.color = .tintColor
            if let period = password?.otpPeriod {
                let countdown = countdown ?? CountdownView()
                countdown.update(period: period)
                cell.accessoryView = countdown
            }
        case .notes:
            content = .cell()
            content.text = row.value
        case .raw:
            content = .cell()
            content.text = row.key
            cell.accessoryType = .disclosureIndicator
        case .field, .header:
            break
        }
        cell.contentConfiguration = content
    }

    /// Splits a code in two halves, the way codes are usually printed and read out.
    private static func grouped(_ code: String) -> String {
        guard code.count >= 6, code.allSatisfy(\.isNumber) else {
            return code
        }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[..<middle]) \(code[middle...])"
    }

    override func numberOfSections(in _: UITableView) -> Int {
        tableData.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableData[section].rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard tableData[indexPath.section].rows[indexPath.row].kind == .header, let passwordEntity else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            configure(cell, at: indexPath)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "header", for: indexPath)
        cell.contentConfiguration = UIHostingConfiguration {
            PasswordDetailHeader(name: passwordEntity.name, folder: passwordEntity.dirText, isSynced: !passwordEntity.hasUnsyncedChanges)
        }
        cell.backgroundConfiguration = .clear()
        cell.selectionStyle = .none
        return cell
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

    override func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        tableData[indexPath.section].rows[indexPath.row].kind != .header
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = tableData[indexPath.section].rows[indexPath.row]
        switch row.kind {
        case .header:
            break
        case .raw:
            performSegue(withIdentifier: "showRawPasswordSegue", sender: self)
        default:
            if row.kind == .secret {
                reveal(indexPath)
            }
            let rect = tableView.rectForRow(at: indexPath)
            editMenuInteraction.presentEditMenu(with: UIEditMenuConfiguration(identifier: indexPath as NSIndexPath, sourcePoint: CGPoint(x: rect.midX, y: rect.minY)))
        }
    }

    // MARK: - Edit menu

    func editMenuInteraction(_: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions _: [UIMenuElement]) -> UIMenu? {
        guard let indexPath = configuration.identifier as? IndexPath else {
            return nil
        }
        let row = tableData[indexPath.section].rows[indexPath.row]
        var actions = [
            UIAction(title: "Copy".localize(), image: UIImage(systemName: "doc.on.doc")) { _ in
                SecurePasteboard.shared.copy(textToCopy: row.value)
            },
        ]
        switch row.kind {
        case .link:
            actions.append(
                UIAction(title: "OpenWebsite".localize(), image: UIImage(systemName: "safari")) { [weak self] _ in
                    self?.openLink(to: row.value)
                }
            )
        case .oneTimePassword where password?.otpType == .hotp:
            actions.append(
                UIAction(title: "NextPassword".localize(), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                    self?.getNextHOTP()
                }
            )
        default:
            break
        }
        return UIMenu(children: actions)
    }

    func editMenuInteraction(_: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        guard let indexPath = configuration.identifier as? IndexPath else {
            return .null
        }
        return tableView.rectForRow(at: indexPath)
    }

    func editMenuInteraction(_: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration, animator _: any UIEditMenuInteractionAnimating) {
        guard let indexPath = configuration.identifier as? IndexPath else {
            return
        }
        if revealed == indexPath {
            reveal(nil)
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

private struct PasswordDetailHeader: View {
    let name: String
    let folder: String
    let isSynced: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var tileSize = 72.0

    private static let palette: [Color] = [.red, .orange, .green, .teal, .blue, .indigo, .purple, .pink, .brown]

    /// Stays the same across launches, unlike `hashValue`.
    private var color: Color {
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[hash % Self.palette.count]
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(name.prefix(1).uppercased())
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: tileSize, height: tileSize)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: tileSize * 0.225, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if !isSynced {
                        Circle()
                            .fill(.orange)
                            .frame(width: tileSize * 0.26, height: tileSize * 0.26)
                            .padding(tileSize * 0.04)
                            .background(Color(uiColor: .systemGroupedBackground), in: Circle())
                            .offset(x: tileSize * 0.1, y: -tileSize * 0.1)
                    }
                }
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if !folder.isEmpty {
                Text(folder)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSynced ? "" : "NotSynced".localize())
    }
}

/// A ring that empties as a time-based one-time password runs out.
private class CountdownView: UIView {
    private var remaining: TimeInterval = 0
    private var period: TimeInterval = 30

    private let label: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textAlignment = .center
        return label
    }()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = false
        label.frame = bounds
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var color: UIColor {
        remaining <= 5 ? .systemRed : .secondaryLabel
    }

    func update(period: TimeInterval) {
        self.period = period
        remaining = period - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        label.text = String(Int(remaining))
        label.textColor = color
        setNeedsDisplay()
    }

    override func draw(_: CGRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 1.5
        let track = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        track.lineWidth = 2.5
        UIColor.tertiarySystemFill.setStroke()
        track.stroke()
        let start = -CGFloat.pi / 2
        let arc = UIBezierPath(arcCenter: center, radius: radius, startAngle: start, endAngle: start + 2 * .pi * remaining / period, clockwise: true)
        arc.lineWidth = 2.5
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }
}
