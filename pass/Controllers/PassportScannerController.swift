//
//  PassportScannerController.swift
//  pass
//

import UIKit

final class PassportScannerController: QRScannerController, QRScannerControllerDelegate {
    var onScan: ((Passport) -> Void)?

    private var scanner = PassportScanner()
    private var passport: Passport?

    override func viewDidLoad() {
        delegate = self
        title = "SetUpFromComputer".localize()
        idleMessage = "ScanPassport.".localize()
        super.viewDidLoad()
    }

    func checkScannedOutput(line: String) -> (accepted: Bool, message: String) {
        switch scanner.add(frame: line) {
        case .unrecognized:
            return (false, "ScanPassport.".localize())
        case let .scanned(count, total):
            idleMessage = "ScannedPassport(%d,%d)".localize(count, total)
            return (false, idleMessage)
        case let .completed(text):
            do {
                passport = try Passport(parsing: text)
                return (true, "Done".localize())
            } catch {
                scanner.reset()
                idleMessage = "InvalidPassport.".localize()
                return (false, idleMessage)
            }
        }
    }

    func handleScannedOutput(line _: String) {}

    override func didClose() {
        if let passport {
            onScan?(passport)
        }
    }
}
