import Foundation
import CoreMIDI
import IOKit

final class DeviceStatus: ObservableObject {
    static let driverPath = "/Library/Audio/MIDI Drivers/DM2USBMIDIDriver.plugin"
    static let ledFixPath = "/Library/Extensions/DM2LEDFix.kext"

    @Published private(set) var driverInstalled = false
    @Published private(set) var ledFixInstalled = false
    @Published private(set) var usbConnected = false
    @Published private(set) var driverRunning = false

    private var midiClient = MIDIClientRef()
    private var timer: Timer?

    init() {
        // The driver runs inside MIDIServer, which macOS only starts for a CoreMIDI client.
        // Being a client keeps the driver loaded, so settings and commands reach it while this app is open.
        MIDIClientCreate("DM2 Settings" as CFString, nil, nil, &midiClient)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    deinit {
        timer?.invalidate()
        if midiClient != 0 { MIDIClientDispose(midiClient) }
    }

    func refresh() {
        let fm = FileManager.default
        set(\.driverInstalled, fm.fileExists(atPath: DeviceStatus.driverPath))
        set(\.ledFixInstalled, fm.fileExists(atPath: DeviceStatus.ledFixPath))
        set(\.usbConnected, DeviceStatus.findUSBDevice())
        set(\.driverRunning, DeviceStatus.findOnlineMIDIDevice())
    }

    // Only publish real changes, so the 2 second poll does not redraw the window.
    private func set(_ key: ReferenceWritableKeyPath<DeviceStatus, Bool>, _ value: Bool) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    /// The DM2 on USB: vendor 0x0665, product 0x0301.
    private static func findUSBDevice() -> Bool {
        guard let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary? else { return false }
        matching["idVendor"] = 0x0665
        matching["idProduct"] = 0x0301
        // Port 0 is the default main port on every macOS version (kIOMainPortDefault is macOS 12+).
        let service = IOServiceGetMatchingService(0, matching)
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }

    /// The MIDI device the driver creates ("DM2" by "MixMan"). It stays in the MIDI setup after
    /// unplugging, marked offline, so only an online one means the driver is running the DM2.
    private static func findOnlineMIDIDevice() -> Bool {
        for i in 0..<MIDIGetNumberOfDevices() {
            let device = MIDIGetDevice(i)
            guard stringProperty(device, kMIDIPropertyName) == "DM2",
                  stringProperty(device, kMIDIPropertyManufacturer) == "MixMan" else { continue }
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(device, kMIDIPropertyOffline, &offline)
            if offline == 0 { return true }
        }
        return false
    }

    private static func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr, let string = value else { return nil }
        return string.takeRetainedValue() as String
    }
}
