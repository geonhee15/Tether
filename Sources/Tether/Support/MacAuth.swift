import Foundation
import LocalAuthentication

/// Asks macOS to confirm that the person at the keyboard owns this Mac (Touch ID, Apple Watch
/// or the login password). Tether's data is only as private as the Mac account it lives in, so
/// that is the right proof for resetting a forgotten Space password.
@MainActor
enum MacAuth {
    enum Outcome {
        case confirmed
        case cancelled
        case failed(String)
        /// This Mac has no password or biometrics to check against.
        case unavailable
    }

    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// `reason` completes the system sentence "Tether is trying to …".
    static func confirm(reason: String, completion: @escaping @MainActor (Outcome) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(.unavailable)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, failure in
            let outcome: Outcome
            if success {
                outcome = .confirmed
            } else if let code = (failure as? LAError)?.code, [.userCancel, .appCancel, .systemCancel].contains(code) {
                outcome = .cancelled
            } else {
                outcome = .failed(failure?.localizedDescription ?? "")
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}
