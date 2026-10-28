import Foundation
import IOKit

/// Lid state of a MacBook, read from the power manager's `AppleClamshellState` property.
public enum Clamshell {
    /// true when the lid is closed; false when it is open or the Mac has no lid.
    public static var isClosed: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                                    kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? Bool) ?? false
    }
}
