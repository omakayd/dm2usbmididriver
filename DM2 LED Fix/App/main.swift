//
//  main.swift
//  DM2 LED Fix: installs or removes the DM2 descriptor-fix driver extension.
//

import AppKit
import SystemExtensions

let driverID = "com.omakayd.DM2LEDFix.Driver"

final class Controller: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "")

    func applicationDidFinishLaunching(_ note: Notification) {
        let title = NSTextField(labelWithString: "Mixman DM2 LED Fix")
        title.font = .boldSystemFont(ofSize: 15)
        let info = NSTextField(wrappingLabelWithString:
            "Installs a driver extension that corrects the DM2's USB endpoint description, " +
            "so macOS can send LED data to it. After installing, approve it in System Settings, " +
            "then unplug and replug the DM2.")
        let install = NSButton(title: "Install", target: self, action: #selector(installClicked))
        install.keyEquivalent = "\r"
        let remove = NSButton(title: "Uninstall", target: self, action: #selector(removeClicked))
        status.stringValue = "Ready."
        status.textColor = .secondaryLabelColor

        let buttons = NSStackView(views: [remove, install])
        let stack = NSStackView(views: [title, info, buttons, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "DM2 LED Fix"
        window.contentView = NSView()
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            info.widthAnchor.constraint(equalToConstant: 400),
            status.widthAnchor.constraint(equalToConstant: 400),
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func installClicked() {
        setStatus("Requesting install...")
        let req = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: driverID, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    @objc private func removeClicked() {
        setStatus("Requesting uninstall...")
        let req = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: driverID, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    private func setStatus(_ s: String) {
        status.stringValue = s
        NSLog("DM2LEDFix: %@", s)
    }

    // MARK: OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        setStatus("Approval needed: open System Settings > General > Login Items & Extensions > " +
                  "Driver Extensions and turn on DM2 LED Fix.")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            setStatus("Done. Unplug the DM2 and plug it back in.")
        case .willCompleteAfterReboot:
            setStatus("Done. Restart the Mac to finish.")
        @unknown default:
            setStatus("Finished (result \(result.rawValue)).")
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let e = error as NSError
        setStatus("Failed: \(e.localizedDescription) (\(e.domain) \(e.code))")
    }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
