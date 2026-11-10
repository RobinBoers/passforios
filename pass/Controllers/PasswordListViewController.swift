//
//  PasswordListViewController.swift
//  pass
//

import passKit
import UIKit

/// The passwords in a folder, or in the whole store at the root, with search and syncing.
final class PasswordListViewController: UITableViewController, PasswordAlertPresenter {
    private enum Section {
        case folders, passwords
    }

    private let folder: PasswordEntity?
    private let folderPath: String?
    private lazy var passwordManager = PasswordManager(viewController: self)
    private lazy var dataSource = makeDataSource()
    private var entries = [String: PasswordTableEntry]()
    private let searchController = UISearchController(searchResultsController: nil)

    /// The sync finished while the list was still pulled down; the refresh ends once it is let go.
    private var isSyncFinished = false
    /// Kept apart from the refresh control, which is replaced after every refresh.
    private var refreshTitle: NSAttributedString?
    private var syncStatusGeneration = 0

    private lazy var addButton = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [unowned self] _ in
        addPassword()
    })

    private lazy var settingsButton = UIBarButtonItem(image: UIImage(systemName: "gearshape"), primaryAction: UIAction { [unowned self] _ in
        presentSettings()
    })

    private lazy var syncButton = UIBarButtonItem(image: UIImage(systemName: "arrow.triangle.2.circlepath"), primaryAction: UIAction { [unowned self] _ in
        sync()
    })

    private var isRoot: Bool {
        folder == nil
    }

    init(folder: PasswordEntity? = nil) {
        self.folder = folder
        self.folderPath = folder?.path
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        if !isRoot {
            tableView.removeTopSpace()
        }
        tableView.dataSource = dataSource

        navigationItem.title = folder?.name ?? "PasswordStore".localize()
        navigationItem.largeTitleDisplayMode = isRoot ? .always : .never

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        if #available(iOS 26.0, *) {
            navigationItem.preferredSearchBarPlacement = .integrated
            toolbarItems = [navigationItem.searchBarPlacementBarButtonItem, .fixedSpace(0), addButton]
        } else {
            navigationItem.rightBarButtonItem = addButton
        }

        if isRoot {
            installRefreshControl()
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

        showSyncStatus(nil)
        reload(animated: false)
        updateBarButtons()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(toolbarItems == nil, animated: animated)
        updateBarButtons()
    }

    // MARK: - Content

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, String> {
        UITableViewDiffableDataSource(tableView: tableView) { [unowned self] tableView, indexPath, path in
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
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
            cell.contentConfiguration = content
            cell.accessoryType = entry.isDir ? .disclosureIndicator : .none
            cell.accessoryView = entry.isSynced ? nil : UIImageView(image: UIImage(systemName: "arrow.triangle.2.circlepath", withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote)))
            cell.accessoryView?.tintColor = .secondaryLabel
            return cell
        }
    }

    private var isSearching: Bool {
        searchController.isActive && !(searchController.searchBar.text ?? "").isEmpty
    }

    /// Folders first, then passwords, each in their own group; a search covers every password in the store.
    private func reload(animated: Bool) {
        let store = PasswordStore.shared
        let query = searchController.searchBar.text ?? ""
        let all: [PasswordEntity] = {
            if !query.isEmpty {
                return store.fetchPasswordEntityCoreData(withDir: false)
            }
            return Defaults.isShowFolderOn ? store.fetchPasswordEntityCoreData(parent: folder) : store.fetchPasswordEntityCoreData(withDir: false)
        }()
        let shown = all
            .map(PasswordTableEntry.init)
            .filter { query.isEmpty || $0.matches(query) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        entries = Dictionary(shown.map { ($0.passwordEntity.path, $0) }, uniquingKeysWith: { first, _ in first })

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
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: animated)

        tableView.backgroundView = isRoot && !store.repositoryExists() ? makeSetUpView() : nil
    }

    @objc
    private func storeChanged() {
        DispatchQueue.main.async { [self] in
            // Entities are recreated on every change; a folder that is gone takes the list back to the root.
            if let folderPath, PasswordStore.shared.fetchPasswordEntity(with: folderPath) == nil {
                navigationController?.popToRootViewController(animated: true)
                return
            }
            reload(animated: !(refreshControl?.isRefreshing ?? false))
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
        guard let path = dataSource.itemIdentifier(for: indexPath), let entry = entries[path] else {
            return
        }
        if entry.isDir {
            navigationController?.pushViewController(PasswordListViewController(folder: entry.passwordEntity), animated: true)
            return
        }
        guard PGPAgent.shared.isPrepared else {
            Utils.alert(title: "CannotShowPassword".localize(), message: "PgpKeyNotSet.".localize(), controller: self)
            return
        }
        let detail = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "passwordDetail") as! PasswordDetailTableViewController
        detail.passwordEntity = entry.passwordEntity
        navigationController?.pushViewController(detail, animated: true)
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
            ])
        })
    }

    private func addPassword() {
        guard PGPAgent.shared.isPrepared, PasswordStore.shared.gitRepository != nil else {
            Utils.alert(title: "CannotAddPassword".localize(), message: "MakeSurePgpAndGitProperlySet.".localize(), controller: self)
            return
        }
        let navigation = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "addPassword") as! UINavigationController
        if let add = navigation.topViewController as? AddPasswordTableViewController, let folderPath {
            add.defaultDirPrefix = "\(folderPath)/"
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
        guard PasswordStore.shared.repositoryExists() else {
            refreshControl?.endRefreshing()
            return
        }
        isSyncFinished = false
        // The header stays as it is while the refresh control shows: changing the subtitle or the buttons then
        // relays out the navigation bar mid-animation, which leaves the list scrolled down.
        syncRepository(status: { _ in }, completion: { [weak self] _ in
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
        // Since iOS 27 an ended refresh control keeps its height reserved at the top, so the list bounces back
        // too far. Detaching it gives that back, the list then returns to the actual top, and as a detached
        // control never fires again, a new one takes its place.
        refreshControl = nil
        tableView.layoutIfNeeded()
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: true)
        DispatchQueue.main.async { [weak self] in
            self?.installRefreshControl()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showLastSynced()
            self?.updateBarButtons()
        }
    }

    override func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {
        endRefreshingIfReleased()
    }

    private func installRefreshControl() {
        let control = UIRefreshControl()
        control.attributedTitle = refreshTitle
        control.addTarget(self, action: #selector(refresh), for: .valueChanged)
        refreshControl = control
    }

    /// Pulls when the app opens, unless there are local changes to push, which is left to the user.
    @objc
    private func syncAutomatically() {
        let store = PasswordStore.shared
        let isRecent = store.lastSyncedTime.map { Date().timeIntervalSince($0) < 60 } ?? false
        guard store.repositoryExists(), store.numberOfLocalCommits == 0, !isRecent,
              refreshControl?.isRefreshing == false, presentedViewController == nil else {
            return
        }
        syncRepository(interactive: false) { [weak self] status in
            self?.showSyncStatus(status)
        } completion: { [weak self] success in
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

    /// The status shows under the title while syncing and for a while after, as Mail shows it. The line stays
    /// when empty: a header that changes height leaves the list scrolled under it.
    private func showSyncStatus(_ status: String?) {
        guard isRoot else {
            return
        }
        if #available(iOS 26.0, *) {
            let text = status ?? " "
            navigationItem.subtitle = text
            var subtitle = AttributedString(text)
            subtitle.uiKit.font = .preferredFont(forTextStyle: .subheadline)
            subtitle.uiKit.foregroundColor = .secondaryLabel
            navigationItem.largeAttributedSubtitle = subtitle
        } else {
            refreshTitle = status.map { NSAttributedString(string: $0) }
            refreshControl?.attributedTitle = refreshTitle
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

        let message = UILabel()
        message.text = "SetUpFromComputer.".localize()
        message.font = .preferredFont(forTextStyle: .body)
        message.textColor = .secondaryLabel

        var configuration = UIButton.Configuration.borderedProminent()
        configuration.title = "SetUp".localize()
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [unowned self] _ in
            presentOnboarding()
        })

        let stack = UIStackView(arrangedSubviews: [image, title, message, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(24, after: message)
        for label in [title, message] {
            label.adjustsFontForContentSizeCategory = true
            label.textAlignment = .center
            label.numberOfLines = 0
        }
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
