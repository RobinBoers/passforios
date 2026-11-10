//
//  ProgressSheet.swift
//  pass
//

import UIKit

enum Feedback {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

extension UIViewController {
    var topmostPresentedViewController: UIViewController {
        guard let presentedViewController, !presentedViewController.isBeingDismissed else {
            return self
        }
        return presentedViewController.topmostPresentedViewController
    }
}

/// A sheet that blocks the screen while long-running work like a sync or clone is in progress.
final class ProgressSheet: UIViewController {
    private static weak var current: ProgressSheet?

    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var hasAppeared = false
    private var pendingDismissal: (() -> Void)?

    static func show(_ status: String, on controller: UIViewController) {
        if let current {
            current.statusLabel.text = status
            return
        }
        let sheet = ProgressSheet()
        sheet.statusLabel.text = status
        sheet.isModalInPresentation = true
        sheet.sheetPresentationController?.detents = [.custom { _ in 140 }]
        current = sheet
        controller.topmostPresentedViewController.present(sheet, animated: true)
    }

    static func update(progress: Float, status: String) {
        guard let current, progress.isFinite else {
            return
        }
        current.statusLabel.text = status
        current.activityIndicator.stopAnimating()
        current.progressView.isHidden = false
        current.progressView.setProgress(progress, animated: true)
    }

    static func dismiss(completion: (() -> Void)? = nil) {
        guard let sheet = current else {
            completion?()
            return
        }
        current = nil
        guard sheet.presentingViewController != nil else {
            completion?()
            return
        }
        guard sheet.hasAppeared else {
            // Dismissing while the presentation is still animating is ignored by UIKit.
            sheet.pendingDismissal = { completion?() }
            return
        }
        sheet.dismiss(animated: true, completion: completion)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        progressView.isHidden = true
        activityIndicator.startAnimating()

        let stack = UIStackView(arrangedSubviews: [statusLabel, activityIndicator, progressView])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        if let pendingDismissal {
            dismiss(animated: true, completion: pendingDismissal)
        }
    }
}
