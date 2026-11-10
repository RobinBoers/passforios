//
//  AppLock.swift
//  passKit
//

import LocalAuthentication

/// Locks the app and its extensions behind Face ID or Touch ID, falling back to the device passcode.
public enum AppLock {
    private static let legacyPasscodeKey = Globals.bundleIdentifier + "passcode"

    public static var isEnabled: Bool {
        get {
            // The app used to have a passcode of its own, which this lock replaces.
            if AppKeychain.shared.contains(key: legacyPasscodeKey) {
                AppKeychain.shared.removeContent(for: legacyPasscodeKey)
                Defaults.isAppLockOn = true
            }
            return Defaults.isAppLockOn
        }
        set {
            Defaults.isAppLockOn = newValue
        }
    }

    /// Face ID, Touch ID or Passcode, whichever the device unlocks with.
    public static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Passcode".localize()
        }
    }

    public static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    public static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
