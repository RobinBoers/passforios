//
//  LabelTableViewCell.swift
//  pass
//
//  Created by Mingshen Sun on 2/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import passKit
import UIKit

struct LabelTableViewCellData {
    var title: String
    var content: String
    var isSecret = false
}

class LabelTableViewCell: UITableViewCell {
    @IBOutlet var contentLabel: UILabel!
    @IBOutlet var titleLabel: UILabel!

    private enum CellType {
        case secret, URL, HOTP, other
    }

    private var type = CellType.other
    private var isReveal = false

    weak var delegatePasswordTableView: PasswordDetailTableViewController?

    private lazy var revealButton: UIButton = {
        let button = UIButton(type: .system)
        button.addTarget(self, action: #selector(reversePasswordDisplay), for: .touchUpInside)
        return button
    }()

    private lazy var nextHOTPButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        button.accessibilityLabel = "NextPassword".localize()
        button.addTarget(self, action: #selector(getNextHOTP), for: .touchUpInside)
        return button
    }()

    var cellData: LabelTableViewCellData? {
        didSet {
            guard let cellData else {
                type = .other
                return
            }
            titleLabel.text = cellData.title
            if cellData.title.caseInsensitiveCompare("HmacBased".localize()) == .orderedSame {
                type = .HOTP
            } else if cellData.isSecret {
                type = .secret
            } else if cellData.title.lowercased().contains("url") {
                type = .URL
            } else {
                type = .other
            }
            render()
            updateButtons()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isReveal = false
    }

    func menuActions() -> [UIAction] {
        var actions = [
            UIAction(title: "Copy".localize(), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                SecurePasteboard.shared.copy(textToCopy: self?.cellData?.content)
            },
        ]
        switch type {
        case .HOTP, .secret:
            actions.append(
                UIAction(title: (isReveal ? "Conceal" : "Reveal").localize(), image: UIImage(systemName: isReveal ? "eye.slash" : "eye")) { [weak self] _ in
                    self?.reversePasswordDisplay()
                }
            )
        case .URL:
            actions.append(
                UIAction(title: "CopyAndOpen".localize(), image: UIImage(systemName: "safari")) { [weak self] _ in
                    self?.delegatePasswordTableView?.openLink(to: self?.cellData?.content)
                }
            )
        case .other:
            break
        }
        if type == .HOTP {
            actions.append(
                UIAction(title: "NextPassword".localize(), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                    self?.getNextHOTP()
                }
            )
        }
        return actions
    }

    private func render() {
        let content = cellData?.content ?? ""
        switch type {
        case .secret:
            contentLabel.font = Globals.passwordFont
            if isReveal {
                contentLabel.attributedText = Utils.attributedPassword(plainPassword: content)
            } else {
                contentLabel.textColor = .label
                contentLabel.text = content.isEmpty ? "" : Globals.passwordDots
            }
        case .HOTP:
            contentLabel.font = Globals.passwordFont
            contentLabel.text = isReveal ? content : Globals.oneTimePasswordDots
        case .other, .URL:
            contentLabel.font = .preferredFont(forTextStyle: .body)
            contentLabel.textColor = .label
            contentLabel.text = content
        }
    }

    @objc
    private func reversePasswordDisplay() {
        isReveal.toggle()
        render()
        updateRevealButton()
    }

    @objc
    private func getNextHOTP() {
        delegatePasswordTableView?.getNextHOTP()
    }

    private func updateRevealButton() {
        revealButton.setImage(UIImage(systemName: isReveal ? "eye.slash" : "eye"), for: .normal)
        revealButton.accessibilityLabel = (isReveal ? "Conceal" : "Reveal").localize()
    }

    private func updateButtons() {
        updateRevealButton()
        switch type {
        case .secret where cellData?.content.isEmpty == false:
            revealButton.sizeToFit()
            accessoryView = revealButton
        case .HOTP:
            let stack = UIStackView(arrangedSubviews: [nextHOTPButton, revealButton])
            stack.spacing = 12
            stack.frame.size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            accessoryView = stack
        default:
            accessoryView = nil
        }
    }
}
