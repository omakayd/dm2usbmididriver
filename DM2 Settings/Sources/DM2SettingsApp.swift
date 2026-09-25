import SwiftUI
import AppKit

@main
struct DM2SettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}   // one settings window is enough
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @StateObject private var settings = DriverSettings()
    @StateObject private var status = DeviceStatus()
    @State private var selectedBank = 0
    @State private var confirmRestore = false

    private let labelWidth: CGFloat = 150
    private static let guideURL = URL(string: "https://github.com/omakayd/dm2usbmididriver/blob/master/LED_CONTROL.md")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBox
            modeBox
            padsBox
            clockBox
            actions
            footer
        }
        .padding(20)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.load()
            status.refresh()
        }
        .onChange(of: settings.softwareMode) { mode in
            if selectedBank >= mode.bankCount { selectedBank = 0 }
        }
        .alert(isPresented: $confirmRestore) {
            Alert(title: Text("Restore default settings?"),
                  message: Text("All DM2 settings go back to the driver defaults: Generic MIDI, pads light when pressed."),
                  primaryButton: .destructive(Text("Restore")) { settings.restoreDefaults() },
                  secondaryButton: .cancel())
        }
    }

    // MARK: Status

    private var statusBox: some View {
        GroupBox(label: Text("Status")) {
            VStack(alignment: .leading, spacing: 6) {
                statusRow("MIDI driver",
                          ok: status.driverInstalled,
                          text: status.driverInstalled ? "Installed" : "Not found in /Library/Audio/MIDI Drivers")
                statusRow("LED fix",
                          ok: status.ledFixInstalled,
                          text: status.ledFixInstalled ? "Installed" : "Not installed, so the LEDs will stay dark")
                statusRow("DM2",
                          ok: status.driverRunning,
                          warn: status.usbConnected && !status.driverRunning,
                          text: dm2StatusText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var dm2StatusText: String {
        if status.driverRunning { return "Connected and running" }
        if status.usbConnected { return "Plugged in, but the driver is not running it (unplug and replug the DM2)" }
        return "Not connected"
    }

    private func statusRow(_ label: String, ok: Bool, warn: Bool = false, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : (warn ? "exclamationmark.triangle.fill" : "xmark.circle.fill"))
                .foregroundColor(ok ? .green : (warn ? .orange : .secondary))
            Text(label).frame(width: 90, alignment: .leading)
            Text(text).foregroundColor(.secondary)
        }
    }

    // MARK: Mode

    private var modeBox: some View {
        GroupBox(label: Text("Software Mode")) {
            VStack(alignment: .leading, spacing: 6) {
                Picker(selection: $settings.softwareMode, label: EmptyView()) {
                    ForEach(SoftwareMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                caption(settings.softwareMode.summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    // MARK: Pads and LEDs

    private var padsBox: some View {
        GroupBox(label: Text("Pads and LEDs")) {
            VStack(alignment: .leading, spacing: 10) {
                if settings.softwareMode.bankCount == 0 {
                    caption("Traktor mode uses its own fixed pad and LED behaviour, so these settings do not apply.")
                } else {
                    if settings.softwareMode.bankCount > 1 {
                        Picker(selection: $selectedBank, label: EmptyView()) {
                            ForEach(0..<4) { Text("Bank \($0 + 1)").tag($0) }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden()
                    }
                    bankSettings(bank: $settings.banks[selectedBank])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func bankSettings(bank: Binding<BankSettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("LEDs follow") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: bank.ledControl, label: EmptyView()) {
                        ForEach(LEDControl.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(width: 320)
                    caption(bank.wrappedValue.ledControl.summary)
                }
            }
            row("Buttons") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Sticky (latching) buttons", isOn: bank.stickyButtons)
                    caption(bank.wrappedValue.stickyButtons
                            ? "Each press toggles the pad: Note On, then Note Off on the next press."
                            : "Pads are momentary: Note On while held, Note Off on release.")
                }
            }
            row("Display") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Invert LEDs (lit when off)", isOn: bank.invertLEDs)
                    Toggle("Show incoming MIDI clock on the pads", isOn: bank.showsMIDIClock)
                    if bank.wrappedValue.showsMIDIClock {
                        caption("The pads show the beat from MIDI clock sent to the DM2, in place of pad state.")
                    }
                }
            }
            row("Scratch ring filter") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: bank.bumpIgnore, label: EmptyView()) {
                        Text("Off").tag(0)
                        ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    caption("Ignores slow scratch ring movement, so bumping a ring sends nothing. Higher ignores more.")
                }
            }
        }
    }

    // MARK: Clock

    private var clockBox: some View {
        GroupBox(label: Text("MIDI Clock Display")) {
            VStack(alignment: .leading, spacing: 6) {
                Picker(selection: $settings.clockResolution, label: EmptyView()) {
                    ForEach(ClockResolution.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
                caption("Used by banks with \"Show incoming MIDI clock\" turned on.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    // MARK: Actions and footer

    private var actions: some View {
        HStack {
            // These talk to the running driver, so they only do something while it is running the DM2.
            Group {
                Button("Clear LEDs") { DriverSettings.send("Clear All LEDs") }
                    .help("Turns every pad LED off")
                Button("Reset Joystick Calibration") { DriverSettings.send("Reset Calibration") }
                    .help("Forgets the learned joystick and slider range")
                Button("Reset Interface") { DriverSettings.send("Reset Interface") }
                    .help("Restarts the driver's USB connection to the DM2")
            }
            .disabled(!status.driverRunning)
            Spacer()
            Button("Restore Defaults...") { confirmRestore = true }
        }
    }

    private var footer: some View {
        HStack {
            caption("Changes apply immediately while the DM2 is connected.")
            Spacer()
            Link("LED control guide", destination: ContentView.guideURL)
                .font(.caption)
        }
    }

    // MARK: Helpers

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label + ":")
                .frame(width: labelWidth, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
