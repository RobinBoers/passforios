//
//  FieldTableViewCell.swift
//  pass
//

import passKit
import UIKit

class FieldTableViewCell: UITableViewCell {
    let keyTextField = UITextField()
    let valueTextField = UITextField()
    private let secretButton = UIButton(type: .system)

    var onChange: ((Field) -> Void)?

    private var field = Field(key: "", value: "") {
        didSet {
            render()
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        keyTextField.placeholder = "Key".localize()
        keyTextField.font = .preferredFont(forTextStyle: .subheadline)
        keyTextField.textColor = .secondaryLabel
        keyTextField.adjustsFontForContentSizeCategory = true
        keyTextField.autocapitalizationType = .none
        keyTextField.autocorrectionType = .no
        keyTextField.spellCheckingType = .no
        keyTextField.setContentHuggingPriority(.required, for: .horizontal)
        keyTextField.addTarget(self, action: #selector(keyChanged), for: .editingChanged)

        valueTextField.placeholder = "Value".localize()
        valueTextField.autocapitalizationType = .none
        valueTextField.autocorrectionType = .no
        valueTextField.spellCheckingType = .no
        valueTextField.clearButtonMode = .whileEditing
        valueTextField.addTarget(self, action: #selector(valueChanged), for: .editingChanged)

        secretButton.addTarget(self, action: #selector(toggleSecret), for: .touchUpInside)
        secretButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [keyTextField, valueTextField, secretButton])
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            keyTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            keyTextField.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.35),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(field: Field) {
        self.field = field
        keyTextField.text = field.key
        valueTextField.text = field.value
    }

    private func render() {
        valueTextField.font = field.isSecret ? Globals.passwordFont : .preferredFont(forTextStyle: .body)
        secretButton.setImage(UIImage(systemName: field.isSecret ? "lock.fill" : "lock.open"), for: .normal)
        secretButton.tintColor = field.isSecret ? .tintColor : .tertiaryLabel
        secretButton.accessibilityLabel = (field.isSecret ? "Secret" : "NotSecret").localize()
    }

    @objc
    private func keyChanged() {
        field.key = keyTextField.text ?? ""
        onChange?(field)
    }

    @objc
    private func valueChanged() {
        field.value = valueTextField.text ?? ""
        onChange?(field)
    }

    @objc
    private func toggleSecret() {
        field.isSecret.toggle()
        onChange?(field)
    }
}
