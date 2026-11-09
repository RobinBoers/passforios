//
//  EditPasswordTableViewController.swift
//  pass
//
//  Created by Mingshen Sun on 12/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import passKit
import UIKit

class EditPasswordTableViewController: PasswordEditorTableViewController {
    override func shouldPerformSegue(withIdentifier identifier: String, sender _: Any?) -> Bool {
        if identifier == "saveEditPasswordSegue" {
            return validate()
        }
        return true
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if segue.identifier == "saveEditPasswordSegue" {
            let (name, path) = getNamePath()
            password!.updatePassword(name: name, path: path, plainText: entry.plainText)
            if let controller = segue.destination as? PasswordDetailTableViewController {
                controller.password = password
            }
        }
    }
}
