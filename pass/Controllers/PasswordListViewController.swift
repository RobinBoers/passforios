//
//  PasswordListViewController.swift
//  pass
//

import OneTimePassword
import passKit
import UIKit

/// The passwords in a folder, or in the whole store at the root, with search and syncing.
final class PasswordListViewController: UITableViewController, PasswordAlertPresenter {
    private enum Section {
        case folders, passwords
    }

    /// By path, as syncing replaces the folder's entity; holding on to it would list the children of one that is gone.
    private let folderPath: String?
    private let folderName: String?
    private lazy var passwordManager = PasswordManager(viewController: self)
    private lazy var dataSource = makeDataSource()
    private var entries = [String: PasswordTableEntry]()
    /// Rows make room for the unsynced dot only when one of them has it.
    private var hasUnsyncedEntries = false
    private let searchController = UISearchController(searchResultsController: nil)

    private var isSyncing = false
    /// The sync finished while the list was still pulled down; the refresh ends once it is let go.
    private var isSyncFinished = false
    private var needsReload = false
    private var syncStatusGeneration = 0

    private lazy var addButton = UIBarButtonItem(systemItem: .add)

    private lazy var settingsButton = UIBarButtonItem(image: UIImage(systemName: "gearshape"), primaryAction: UIAction { [unowned self] _ in
        presentSettings()
    })

    private lazy var syncButton = UIBarButtonItem(image: UIImage(systemName: "arrow.triangle.2.circlepath"), primaryAction: UIAction { [unowned self] _ in
        sync()
    })

    private var isRoot: Bool {
        folderPath == nil
    }

    init(folder: PasswordEntity? = nil) {
        self.folderPath = folder?.path
        self.folderName = folder?.name
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(PasswordListCell.self, forCellReuseIdentifier: "cell")
        if !isRoot {
            tableView.removeTopSpace()
        }
        tableView.dataSource = dataSource

        navigationItem.title = folderName ?? "PasswordStore".localize()
        navigationItem.largeTitleDisplayMode = isRoot ? .automatic : .never

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        if #available(iOS 26.0, *) {
            navigationItem.preferredSearchBarPlacement = .integrated
            toolbarItems = [navigationItem.searchBarPlacementBarButtonItem, .fixedSpace(0), addButton]
        } else {
            navigationItem.rightBarButtonItem = addButton
        }

        if isRoot {
            refreshControl = UIRefreshControl()
            refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        }

        let center = NotificationCenter.default
        for name in [Notification.Name.passwordStoreUpdated, .passwordStoreErased, .passwordDisplaySettingChanged, .passwordStoreChangeDiscarded] {
            center.addObserver(self, selector: #selector(storeChanged), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(updateBarButtons), name: .passwordStoreSyncSucceeded, object: nil)
        if isRoot {
            center.addObserver(self, selector: #selector(syncAutomatically), name: UIApplication.didBecomeActiveNotification, object: nil)
            center.addObserver(self, selector: #selector(startSearching), name: .passwordSearch, object: nil)
        }

        reload(animated: false)
        updateBarButtons()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(toolbarItems == nil, animated: animated)
        updateBarButtons()
        updateAddButton()
    }

    // MARK: - Content

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, String> {
        UITableViewDiffableDataSource(tableView: tableView) { [unowned self] tableView, indexPath, path in
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! PasswordListCell
            guard let entry = entries[path] else {
                return cell
            }
            var content = entry.isDir ? UIListContentConfiguration.valueCell() : UIListContentConfiguration.subtitleCell()
            content.text = entry.title
            if entry.isDir {
                content.image = UIImage(systemName: "folder")
                content.secondaryText = String(entry.passwordEntity.children.count)
            } else if isSearching || !Defaults.isShowFolderOn {
                content.secondaryText = entry.categoryText.isEmpty ? nil : entry.categoryText
                content.secondaryTextProperties.color = .secondaryLabel
            }
            if hasUnsyncedEntries {
                content.directionalLayoutMargins.leading += PasswordListCell.gutter
            }
            cell.contentConfiguration = content
            cell.accessoryType = entry.isDir ? .disclosureIndicator : .none
            cell.isSynced = entry.isSynced
            return cell
        }
    }

    private var isSearching: Bool {
        searchController.isActive && !(searchController.searchBar.text ?? "").isEmpty
    }

    /// Folders first, then passwords, each in their own group; a search covers every password in the store.
    @available(iOS 17.0, *)
    override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
        guard isSearching, entries.isEmpty else {
            contentUnavailableConfiguration = nil
            return
        }
        contentUnavailableConfiguration = UIContentUnavailableConfiguration.search().updated(for: state)
    }

    private func reload(animated: Bool) {
        let store = PasswordStore.shared
        let query = searchController.searchBar.text ?? ""
        let all: [PasswordEntity] = {
            if !query.isEmpty {
                return store.fetchPasswordEntityCoreData(withDir: false)
            }
            guard Defaults.isShowFolderOn else {
                return store.fetchPasswordEntityCoreData(withDir: false)
            }
            let folder = folderPath.flatMap(store.fetchPasswordEntity(with:))
            return folderPath != nil && folder == nil ? [] : store.fetchPasswordEntityCoreData(parent: folder)
        }()
        let shown = all.map(PasswordTableEntry.init).ranked(by: query)
        let previous = entries
        entries = Dictionary(shown.map { ($0.passwordEntity.path, $0) }, uniquingKeysWith: { first, _ in first })
        let hadUnsyncedEntries = hasUnsyncedEntries
        hasUnsyncedEntries = shown.contains { !$0.isSynced }

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        let folders = shown.filter(\.isDir).map(\.passwordEntity.path)
        let passwords = shown.filter { !$0.isDir }.map(\.passwordEntity.path)
        if !folders.isEmpty {
            snapshot.appendSections([.folders])
            snapshot.appendItems(folders, toSection: .folders)
        }
        if !passwords.isEmpty {
            snapshot.appendSections([.passwords])
            snapshot.appendItems(passwords, toSection: .passwords)
        }
        // Entities are recreated on every change, so only rows that look different are redrawn, and nothing
        // is applied when nothing changed: a table that changes while it moves settles in the wrong place.
        let changed = snapshot.itemIdentifiers.filter { path in
            guard let old = previous[path], let new = entries[path] else {
                return false
            }
            return hasUnsyncedEntries != hadUnsyncedEntries || old.title != new.title || old.isSynced != new.isSynced || old.categoryText != new.categoryText
                || old.passwordEntity.children.count != new.passwordEntity.children.count
        }
        if snapshot.itemIdentifiers != dataSource.snapshot().itemIdentifiers || snapshot.sectionIdentifiers != dataSource.snapshot().sectionIdentifiers || !changed.isEmpty {
            snapshot.reconfigureItems(changed)
            dataSource.apply(snapshot, animatingDifferences: animated)
        }

        if #available(iOS 17.0, *) {
            setNeedsUpdateContentUnavailableConfiguration()
        }

        let showsSetUp = isRoot && !store.repositoryExists()
        if showsSetUp != (tableView.backgroundView != nil) {
            tableView.backgroundView = showsSetUp ? makeSetUpView() : nil
        }
    }

    @objc
    private func storeChanged() {
        DispatchQueue.main.async { [self] in
            // A folder that is gone takes the list back to the root.
            if let folderPath, PasswordStore.shared.fetchPasswordEntity(with: folderPath) == nil {
                navigationController?.popToRootViewController(animated: true)
                return
            }
            updateAddButton()
            // The list holds still while a refresh shows; it catches up once that has ended.
            guard refreshControl?.isRefreshing != true else {
                needsReload = true
                return
            }
            reload(animated: true)
            updateBarButtons()
        }
    }

    /// On iOS 26 settings and the sync button sit at the top; before, the tab bar holds settings and a badge.
    @objc
    private func updateBarButtons() {
        guard refreshControl?.isRefreshing != true else {
            return
        }
        let localCommits = PasswordStore.shared.numberOfLocalCommits
        if #available(iOS 26.0, *) {
            syncButton.badge = .count(localCommits)
            navigationItem.rightBarButtonItems = isRoot ? [settingsButton] + (localCommits > 0 ? [syncButton] : []) : nil
        } else {
            navigationController?.tabBarItem.badgeValue = localCommits == 0 ? nil : String(localCommits)
        }
    }

    // MARK: - Selection

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // The rows can outlive their entities while a refresh holds back reloading.
        guard let path = dataSource.itemIdentifier(for: indexPath), let entity = PasswordStore.shared.fetchPasswordEntity(with: path) else {
            return
        }
        if entity.isDir {
            navigationController?.pushViewController(PasswordListViewController(folder: entity), animated: true)
            return
        }
        guard PGPAgent.shared.isPrepared else {
            Utils.alert(title: "CannotShowPassword".localize(), message: "PgpKeyNotSet.".localize(), controller: self)
            return
        }
        showDetail(of: entity)
    }

    private func showDetail(of entity: PasswordEntity) {
        let detail = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "passwordDetail") as! PasswordDetailTableViewController
        detail.passwordEntity = entity
        navigationController?.pushViewController(detail, animated: true)
    }

    /// Puts the verification code of an `otpauth` link into a new entry, or one that exists.
    func setUpOneTimeCode(_ url: URL) {
        guard let token = Token(url: url) else {
            Utils.alert(title: "CannotAddPassword".localize(), message: "InvalidTokenUrl".localize(), controller: self)
            return
        }
        guard PGPAgent.shared.isPrepared, PasswordStore.shared.gitRepository != nil else {
            Utils.alert(title: "CannotAddPassword".localize(), message: "MakeSurePgpAndGitProperlySet.".localize(), controller: self)
            return
        }
        let otpauth = url.absoluteString
        let setup = OneTimeCodeSetupController(issuer: token.issuer, account: token.name)
        setup.onChoose = { [unowned self] choice in
            switch choice {
            case .newEntry:
                let format = Defaults.storeFormat
                let user = token.name.isEmpty ? [] : [Field(key: Constants.USER_KEYWORD, value: token.name)]
                let fields = user + [Field(key: Constants.PASSWORD_KEYWORD, value: "", isSecret: true), Field.oneTimeCode(otpauth, format: format)]
                addPassword(template: Entry(fields: fields, format: format), name: token.issuer)
            case let .entry(path):
                addOneTimeCode(otpauth, toEntryAt: path)
            }
        }
        navigationController?.popToRootViewController(animated: false)
        dismiss(animated: false)
        present(UINavigationController(rootViewController: setup), animated: true)
    }

    /// The code replaces the entry's one code, if asked to, or goes after its last code, its password, or at the end.
    private func addOneTimeCode(_ otpauth: String, toEntryAt path: String) {
        decryptPassword(in: self, with: path) { [unowned self] password in
            var entry = password.entry
            let save = { [unowned self] (replacing: Bool) in
                let codes = entry.fields.indices.filter { entry.fields[$0].isOtpauth }
                if replacing, let index = codes.first {
                    entry.fields[index].value = otpauth
                } else {
                    let after = codes.last ?? entry.fields.firstIndex { $0.key == Constants.PASSWORD_KEYWORD }
                    entry.fields.insert(Field.oneTimeCode(otpauth, format: entry.format), at: after.map { $0 + 1 } ?? entry.fields.count)
                }
                password.updatePassword(name: password.name, path: password.path, plainText: entry.plainText)
                do {
                    guard let entity = PasswordStore.shared.fetchPasswordEntity(with: path),
                          let saved = try PasswordStore.shared.edit(passwordEntity: entity, password: password) else {
                        return
                    }
                    Feedback.success()
                    showDetail(of: saved)
                } catch {
                    Utils.alert(title: "Error".localize(), message: error.localizedDescription, controller: self)
                }
            }
            // With several codes it is unclear which one a new one would replace.
            guard entry.fields.filter(\.isOtpauth).count == 1 else {
                save(false)
                return
            }
            let alert = UIAlertController(title: "ReplaceCode?".localize(), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Replace".localize(), style: .destructive) { _ in save(true) })
            alert.addAction(UIAlertAction(title: "KeepBoth".localize(), style: .default) { _ in save(false) })
            alert.addAction(UIAlertAction.cancel())
            present(alert, animated: true)
        }
    }

    override func tableView(_: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
        guard let path = dataSource.itemIdentifier(for: indexPath), let entry = entries[path], !entry.isDir else {
            return nil
        }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "CopyPassword".localize(), image: UIImage(systemName: "doc.on.doc")) { _ in
                    self?.passwordManager.providePasswordPasteboard(with: path)
                },
                UIAction(title: "Delete".localize(), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.confirmDelete(path)
                },
            ])
        })
    }

    override func tableView(_: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let path = dataSource.itemIdentifier(for: indexPath), let entry = entries[path], !entry.isDir else {
            return nil
        }
        let delete = UIContextualAction(style: .destructive, title: "Delete".localize()) { [unowned self] _, _, completion in
            confirmDelete(path, completion: completion)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    /// By path, as the entity shown may have been replaced by a sync since.
    private func confirmDelete(_ path: String, completion: @escaping (Bool) -> Void = { _ in }) {
        let alert = UIAlertController(title: "DeletePassword?".localize(), message: nil, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(title: "Delete".localize(), style: .destructive) { [unowned self] _ in
                do {
                    guard let passwordEntity = PasswordStore.shared.fetchPasswordEntity(with: path) else {
                        completion(false)
                        return
                    }
                    try PasswordStore.shared.delete(passwordEntity: passwordEntity)
                    completion(true)
                } catch {
                    completion(false)
                    Utils.alert(title: "Error".localize(), message: error.localizedDescription, controller: self)
                }
            }
        )
        alert.addAction(UIAlertAction.cancel { _ in completion(false) })
        present(alert, animated: true)
    }

    /// With protos, adding starts from a menu of them, as `sec add` takes one; without, it starts right away.
    /// In a directory with a default proto, tapping starts from it and holding offers the others.
    private func updateAddButton() {
        let protos = Defaults.storeFormat == .sec ? PasswordStore.shared.protos : [:]
        guard !protos.isEmpty else {
            addButton.menu = nil
            addButton.primaryAction = UIAction(image: UIImage(systemName: "plus")) { [unowned self] _ in
                addPassword()
            }
            return
        }
        let plain = UIAction(title: "Password".localize(), image: UIImage(systemName: "key")) { [unowned self] _ in
            addPassword()
        }
        let known = KnownProto.all.filter { protos[$0.name] != nil }
        let others = protos.keys
            .filter { KnownProto.named($0) == nil }
            .map { KnownProto(name: $0, titleKey: $0.prefix(1).uppercased() + $0.dropFirst(), symbol: "doc.text") }
            .sorted { $0.titleKey.localizedStandardCompare($1.titleKey) == .orderedAscending }
        let split = known.firstIndex { KnownProto.bottom.contains($0.name) } ?? known.count
        let templates = (known[..<split] + others + known[split...]).map { proto in
            UIAction(title: proto.titleKey.localize(), image: UIImage(systemName: proto.symbol)) { [unowned self] _ in
                addPassword(proto: protos[proto.name])
            }
        }
        let defaultProto = PasswordStore.shared.defaultProto(in: folderPath).flatMap { protos[$0] }
        addButton.primaryAction = defaultProto.map { proto in
            UIAction(image: UIImage(systemName: "plus")) { [unowned self] _ in
                addPassword(proto: proto)
            }
        }
        // A menu lists its first items nearest the button, which in the bottom toolbar is at the bottom.
        let isInToolbar = toolbarItems?.contains(addButton) == true
        addButton.menu = UIMenu(children: [plain, UIMenu(options: .displayInline, children: isInToolbar ? templates.reversed() : templates)])
    }

    /// Without a proto, a sec entry starts from a password field, as `sec add` does.
    private func addPassword(proto: String? = nil, template: Entry? = nil, name: String = "") {
        guard PGPAgent.shared.isPrepared, PasswordStore.shared.gitRepository != nil else {
            Utils.alert(title: "CannotAddPassword".localize(), message: "MakeSurePgpAndGitProperlySet.".localize(), controller: self)
            return
        }
        let navigation = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "addPassword") as! UINavigationController
        if let add = navigation.topViewController as? AddPasswordTableViewController {
            if let folderPath {
                add.defaultDirPrefix = "\(folderPath)/"
            }
            if let template {
                add.template = template
            } else if Defaults.storeFormat == .sec {
                add.template = try? Entry(parsing: proto ?? "\(Constants.PASSWORD_KEYWORD)!:", format: .sec)
            }
            add.name = name
        }
        present(navigation, animated: true)
    }

    @IBAction
    private func cancelAddPassword(segue _: UIStoryboardSegue) {}

    @IBAction
    private func saveAddPassword(segue: UIStoryboardSegue) {
        if let controller = segue.source as? AddPasswordTableViewController, let password = controller.password {
            passwordManager.addPassword(with: password)
        }
    }

    @IBAction
    private func cancelEditPassword(segue _: UIStoryboardSegue) {}

    @IBAction
    private func saveEditPassword(segue _: UIStoryboardSegue) {}

    @objc
    private func startSearching() {
        navigationController?.popToRootViewController(animated: false)
        searchController.isActive = true
        searchController.searchBar.becomeFirstResponder()
    }

    // MARK: - Syncing

    private func sync() {
        guard let refreshControl, !refreshControl.isRefreshing else {
            return
        }
        refreshControl.beginRefreshing()
        refresh()
    }

    @objc
    private func refresh() {
        guard !isSyncing, PasswordStore.shared.repositoryExists() else {
            refreshControl?.endRefreshing()
            return
        }
        isSyncing = true
        isSyncFinished = false
        syncRepository(status: { [weak self] status in
            self?.showSyncStatus(status)
        }, completion: { [weak self] _ in
            self?.isSyncing = false
            self?.isSyncFinished = true
            self?.endRefreshingIfReleased()
        })
    }

    /// Like Mail, the refresh only ends once the list is let go.
    private func endRefreshingIfReleased() {
        guard isSyncFinished, !tableView.isDragging else {
            return
        }
        isSyncFinished = false
        refreshControl?.endRefreshing()
        showLastSynced()
        updateBarButtons()
        if needsReload {
            needsReload = false
            reload(animated: true)
        }
    }

    override func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {
        endRefreshingIfReleased()
    }

    /// Pulls when the app opens, unless there are local changes to push, which is left to the user.
    @objc
    private func syncAutomatically() {
        let store = PasswordStore.shared
        let isRecent = store.lastSyncedTime.map { Date().timeIntervalSince($0) < 60 } ?? false
        guard store.repositoryExists(), store.numberOfLocalCommits == 0, !isRecent, !isSyncing, presentedViewController == nil else {
            return
        }
        isSyncing = true
        syncRepository(interactive: false) { [weak self] status in
            self?.showSyncStatus(status)
        } completion: { [weak self] success in
            self?.isSyncing = false
            if success {
                self?.showLastSynced()
            } else {
                self?.showSyncStatus("SyncFailed".localize())
                self?.hideSyncStatus()
            }
        }
    }

    private func showLastSynced() {
        let isRecent = PasswordStore.shared.lastSyncedTime.map { Date().timeIntervalSince($0) < 60 } ?? false
        showSyncStatus(isRecent ? "SyncedJustNow".localize() : "LastSynced(%@)".localize(PasswordStore.shared.lastSyncedTimeString))
        hideSyncStatus()
    }

    /// The status shows under the title while syncing and for a while after, as Mail shows it.
    private func showSyncStatus(_ status: String?) {
        guard isRoot else {
            return
        }
        if #available(iOS 26.0, *) {
            let apply = { [self] in
                navigationItem.subtitle = status
                navigationItem.largeAttributedSubtitle = status.map {
                    var subtitle = AttributedString($0)
                    subtitle.uiKit.font = .preferredFont(forTextStyle: .subheadline)
                    subtitle.uiKit.foregroundColor = .secondaryLabel
                    return subtitle
                }
            }
            // A subtitle coming or going changes the header's height, so the title and the list glide along.
            guard (navigationItem.subtitle == nil) != (status == nil), view.window != nil, refreshControl?.isRefreshing != true else {
                apply()
                return
            }
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) { [self] in
                apply()
                navigationController?.navigationBar.layoutIfNeeded()
                tableView.layoutIfNeeded()
            }
        } else {
            refreshControl?.attributedTitle = status.map { NSAttributedString(string: $0) }
        }
    }

    private func hideSyncStatus() {
        guard #available(iOS 26.0, *) else {
            return
        }
        syncStatusGeneration += 1
        let generation = syncStatusGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, generation == syncStatusGeneration, refreshControl?.isRefreshing == false else {
                return
            }
            showSyncStatus(nil)
        }
    }

    // MARK: - Empty state

    private func makeSetUpView() -> UIView {
        let image = UIImageView(image: UIImage(systemName: "qrcode.viewfinder"))
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle, scale: .large)
        image.tintColor = .secondaryLabel

        let title = UILabel()
        title.text = "NoPasswordStore".localize()
        let titleFont = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
        title.font = UIFont(descriptor: titleFont.withSymbolicTraits(.traitBold) ?? titleFont, size: 0)

        var configuration = UIButton.Configuration.borderedProminent()
        configuration.title = "SetUp".localize()
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [unowned self] _ in
            presentOnboarding()
        })

        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [image, title, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(24, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = UIView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
        ])
        return view
    }
}

// MARK: - Searching

extension PasswordListViewController: UISearchResultsUpdating {
    func updateSearchResults(for _: UISearchController) {
        reload(animated: false)
    }
}

/// Marks entries with changes that are not pushed yet with a dot before them, like unread mail.
private class PasswordListCell: UITableViewCell {
    /// Room before the content for the dot, kept on every row of a list with one so that they line up.
    static let gutter: CGFloat = 20

    private let dot: UIView = {
        let dot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        dot.backgroundColor = .systemOrange
        dot.layer.cornerRadius = 5
        dot.isHidden = true
        return dot
    }()

    var isSynced = true {
        didSet {
            dot.isHidden = isSynced
            accessibilityValue = isSynced ? nil : "NotSynced".localize()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A content configuration brings its own view, so the dot joins it once it is there.
        let content = contentView as? UIListContentView ?? contentView.subviews.lazy.compactMap { $0 as? UIListContentView }.first
        guard let content, let text = content.textLayoutGuide?.layoutFrame else {
            return
        }
        if dot.superview != content {
            content.addSubview(dot)
        }
        let leading = content.imageLayoutGuide?.layoutFrame ?? text
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        dot.center = CGPoint(x: isRightToLeft ? leading.maxX + 12 : leading.minX - 12, y: text.midY)
    }
}
