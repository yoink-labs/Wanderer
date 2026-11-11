import Foundation

/// Debug-only launch routes for screenshots and UI checks, so a build can open
/// straight onto a screen without taps:
///
///     -uiTab trips|explore|profile   start on a tab
///     -uiOpenTrip first              push the first trip on Home
///     -uiSheet expenses|bookings|checklist|share|files|journal|settings
///                                    open a trip sheet after the trip loads
///     -uiDemo YES                    seed a local demo trip for guests
///
/// Appearance and guest mode use the standard UserDefaults argument domain:
/// `-wanderer.appearance dark -wanderer.isGuest YES`.
/// Release builds ignore every flag.
enum DebugLaunch {
    static func value(_ key: String) -> String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-\(key)"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }

    static var tab: String? { value("uiTab") }
    static var opensFirstTrip: Bool { value("uiOpenTrip") != nil }
    static var sheet: String? { value("uiSheet") }
    static var wantsDemo: Bool { value("uiDemo") != nil }
}
