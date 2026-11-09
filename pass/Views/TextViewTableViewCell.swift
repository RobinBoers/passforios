//
//  TextViewTableViewCell.swift
//  pass
//
//  Created by Mingshen Sun on 11/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import UIKit

class TextViewTableViewCell: UITableViewCell {
    @IBOutlet var contentTextView: UITextView!

    override func awakeFromNib() {
        super.awakeFromNib()
        contentTextView.textContainer.lineFragmentPadding = 0
        contentTextView.textContainerInset = .zero
        contentTextView.isScrollEnabled = false
        contentTextView.font = .preferredFont(forTextStyle: .body)
        contentTextView.adjustsFontForContentSizeCategory = true
        contentTextView.textColor = .label
        contentTextView.backgroundColor = .clear
    }

    func getContent() -> String? {
        contentTextView.text
    }

    func setContent(content: String?) {
        contentTextView.text = content
    }
}
