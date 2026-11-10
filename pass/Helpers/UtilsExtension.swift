//
//  UtilsExtension.swift
//  pass
//
//  Created by Yishi Lin on 13/6/17.
//  Copyright © 2017年 Bob Sun. All rights reserved.
//

import Foundation
import passKit
import UIKit

extension Utils {
    static func alert(title: String, message: String, controller: UIViewController, handler: ((UIAlertAction) -> Void)? = nil, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: "Ok".localize(), style: UIAlertAction.Style.default, handler: handler))
        ProgressSheet.dismiss {
            controller.topmostPresentedViewController.present(alert, animated: true, completion: completion)
        }
    }
}

extension UITableView {
    /// Grouped tables leave room above the first group for a header they do not have; under a small title it
    /// reads as a gap.
    func removeTopSpace() {
        tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNonzeroMagnitude))
    }
}
