import Foundation

// The DM2 driver reads its settings from this preferences domain and re-reads them when it
// receives the "Preferences Changed" distributed notification. Keys and values here must match
// DM2USBMIDI.cpp (readSettings) and Configurations/DM2Configuration.cpp (readBankSettings).
let driverDomain = "com.joemattiello.driver.dm2"

enum SoftwareMode: String, CaseIterable, Identifiable {
    case generic = "Generic MIDI"
    case genericWithBanks = "Generic MIDI with Banks"
    case mixxx = "Mixxx"
    case traktor = "Traktor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generic: return "Generic MIDI"
        case .genericWithBanks: return "Generic MIDI with 4 Banks"
        case .mixxx: return "Mixxx"
        case .traktor: return "Traktor"
        }
    }

    /// How many pad banks the driver uses in this mode (Traktor reads none of these settings).
    var bankCount: Int {
        switch self {
        case .generic, .mixxx: return 1
        case .genericWithBanks: return 4
        case .traktor: return 0
        }
    }

    var summary: String {
        switch self {
        case .generic:
            return "Pads send notes 0 to 15 on channel 1. The bottom buttons send their own notes."
        case .genericWithBanks:
            return "Bottom buttons 1 to 4 switch between four pad banks (notes 0-15, 16-31, 32-47, 48-63), each with its own settings."
        case .mixxx:
            return "Mappings for the Mixxx DJ app."
        case .traktor:
            return "Mappings for Native Instruments Traktor, with fixed pad and LED behaviour."
        }
    }
}

enum LEDControl: String, CaseIterable, Identifiable {
    case driver = "Driver Only"
    case midi = "MIDI Messages Only"
    case both = "Driver & MIDI Messages"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driver: return "Pad presses"
        case .midi: return "MIDI from apps"
        case .both: return "Both"
        }
    }

    var summary: String {
        switch self {
        case .driver:
            return "The driver lights pads as you press them. MIDI sent to the DM2 is ignored."
        case .midi:
            return "Only your app controls the LEDs: Note On lights a pad, Note Off turns it off, on the pad's own note."
        case .both:
            return "Pad presses toggle the LEDs, and MIDI from your app can also set them."
        }
    }

    /// The driver compares these strings case-insensitively and treats anything else as "Driver Only".
    init(stored: String?) {
        let match = LEDControl.allCases.first { $0.rawValue.caseInsensitiveCompare(stored ?? "") == .orderedSame }
        self = match ?? .driver
    }
}

enum ClockResolution: String, CaseIterable, Identifiable {
    case sixteenth = "16th"
    case thirtySecond = "32nd"
    case quarter = "1/4"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sixteenth: return "16th notes"
        case .thirtySecond: return "32nd notes"
        case .quarter: return "Flash on quarter notes only"
        }
    }
}

struct BankSettings: Equatable {
    var ledControl: LEDControl = .driver
    var stickyButtons = false
    var invertLEDs = false
    var showsMIDIClock = false
    var bumpIgnore = 0          // 0 = off, 1...10
}

final class DriverSettings: ObservableObject {
    @Published var softwareMode: SoftwareMode = .generic {
        didSet { if !isLoading && softwareMode != oldValue { writeMode() } }
    }
    @Published var clockResolution: ClockResolution = .sixteenth {
        didSet { if !isLoading && clockResolution != oldValue { writeClock() } }
    }
    @Published var banks: [BankSettings] = Array(repeating: BankSettings(), count: 4) {
        didSet { if !isLoading { writeBanks(from: oldValue) } }
    }

    private var isLoading = false
    private let domain = driverDomain as CFString

    init() {
        load()
    }

    // MARK: Reading

    /// Reloads everything from disk, for example after another app or `defaults write` changed it.
    func load() {
        CFPreferencesAppSynchronize(domain)
        isLoading = true
        defer { isLoading = false }

        softwareMode = SoftwareMode(rawValue: readString("softwareMode") ?? "") ?? .generic
        clockResolution = ClockResolution(rawValue: readString("midiClockResolution") ?? "") ?? .sixteenth
        banks = (1...4).map { n in
            BankSettings(
                ledControl: LEDControl(stored: readString("bank\(n)WhoControlsLEDs")),
                stickyButtons: readBool("bank\(n)StickyButtons"),
                invertLEDs: readBool("bank\(n)InvertLeds"),
                showsMIDIClock: readBool("bank\(n)DisplaysMIDIClock"),
                bumpIgnore: min(max(readInt("bank\(n)ScratchRingBumpIgnore"), 0), 10)
            )
        }
    }

    private func readString(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, domain) as? String
    }

    private func readBool(_ key: String) -> Bool {
        var valid: DarwinBoolean = false
        let value = CFPreferencesGetAppBooleanValue(key as CFString, domain, &valid)
        return valid.boolValue && value
    }

    private func readInt(_ key: String) -> Int {
        var valid: DarwinBoolean = false
        let value = CFPreferencesGetAppIntegerValue(key as CFString, domain, &valid)
        return valid.boolValue ? value : 0
    }

    // MARK: Writing

    private func set(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(key as CFString, value, domain)
    }

    private func setBool(_ key: String, _ value: Bool) {
        set(key, value ? kCFBooleanTrue : kCFBooleanFalse)
    }

    private func writeMode() {
        set("softwareMode", softwareMode.rawValue as CFString)
        // The new mode starts from whatever its banks last showed, so start it clean.
        commit(thenSend: "Clear All LEDs")
    }

    private func writeClock() {
        set("midiClockResolution", clockResolution.rawValue as CFString)
        commit()
    }

    private func writeBanks(from old: [BankSettings]) {
        var clearLEDs = false
        for (i, bank) in banks.enumerated() where i < old.count && bank != old[i] {
            let n = i + 1
            let was = old[i]
            if bank.ledControl != was.ledControl { set("bank\(n)WhoControlsLEDs", bank.ledControl.rawValue as CFString) }
            if bank.stickyButtons != was.stickyButtons { setBool("bank\(n)StickyButtons", bank.stickyButtons) }
            if bank.invertLEDs != was.invertLEDs {
                setBool("bank\(n)InvertLeds", bank.invertLEDs)
                // Inverting flips what a stored LED bit means, so reset to the new "all off" state.
                clearLEDs = true
            }
            if bank.showsMIDIClock != was.showsMIDIClock { setBool("bank\(n)DisplaysMIDIClock", bank.showsMIDIClock) }
            if bank.bumpIgnore != was.bumpIgnore {
                set("bank\(n)ScratchRingBumpIgnore", NSNumber(value: bank.bumpIgnore))
            }
        }
        commit(thenSend: clearLEDs ? "Clear All LEDs" : nil)
    }

    private func commit(thenSend extra: String? = nil) {
        CFPreferencesAppSynchronize(domain)
        DriverSettings.send("Preferences Changed")
        if let extra = extra { DriverSettings.send(extra) }
    }

    /// Removes every setting so the driver falls back to its built-in defaults.
    func restoreDefaults() {
        var keys = ["softwareMode", "midiClockResolution"]
        for n in 1...4 {
            keys += ["WhoControlsLEDs", "StickyButtons", "InvertLeds", "DisplaysMIDIClock", "ScratchRingBumpIgnore"]
                .map { "bank\(n)\($0)" }
        }
        keys.forEach { set($0, nil) }
        commit(thenSend: "Clear All LEDs")
        load()
    }

    // MARK: Driver commands

    /// Posts one of the notifications the driver listens for: "Preferences Changed",
    /// "Clear All LEDs", "Reset Calibration" or "Reset Interface".
    static func send(_ name: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(name), object: driverDomain, userInfo: nil, deliverImmediately: true)
    }
}
