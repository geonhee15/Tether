import Foundation
import IOKit.pwr_mgt

/// Holds a power assertion that keeps the Mac and its display from idle-sleeping.
/// (Closing the lid or choosing Sleep from the Apple menu still sleeps the Mac.)
@MainActor
final class SleepGuard {
    static let shared = SleepGuard()

    private var assertion: IOPMAssertionID = 0
    private(set) var isActive = false

    private init() {}

    /// Returns false if macOS refused the assertion.
    @discardableResult
    func start() -> Bool {
        guard !isActive else { return true }
        let reason = "Tether keep-awake mode" as CFString
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion)
        isActive = result == kIOReturnSuccess
        return isActive
    }

    func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        isActive = false
    }
}
