# DM2 LED Control Guide

How to make the Mixman DM2's 16 pad LEDs work on a modern Mac, and how an app can take control of them. It covers both setup and app-driven control, such as latching and momentary pads.

**Status (2026-09-24, Apple Silicon M5, macOS 26.5.2):**
- Verified on hardware: LEDs work with the fix installed, including the startup blink and pad presses toggling their LEDs ("Driver Only" mode).
- Not yet verified on hardware: LEDs controlled by MIDI from an app ("MIDI Messages Only" mode). That part is described from the driver source code.

---

## 1. Enabling LEDs on a modern Mac (one-time setup)

### Why a fix is needed

The DM2 declares its LED endpoint (0x02) as a USB *Bulk* endpoint. Because the DM2 is a low-speed (1.5 Mb/s) device, that is illegal under the USB spec. Current macOS rejects it in software, with this message in the kernel log:

```
IOUSBHostFamily::validateEndpointMaxPacketSize: USB 2.0 5.[5|7].3: endpoint 0x02 invalid wMaxPacketSize 0x0008
```

As a result, the LED pipe is never created, and every LED write fails. MIDI input is unaffected.

The fix is a *codeless kernel extension*: a settings file with no program code. It uses the same mechanism Apple uses for its own faulty USB devices, which is Apple's `AppleUSBHostMergeProperties` class with `kUSBDescriptorOverride`. It hands macOS a corrected copy of the DM2's configuration descriptor, with endpoint 0x02 changed to *Interrupt*. That is legal at low speed and works identically for the DM2.

Only one byte region differs from the device's real descriptor:

```
original: ... 07 05 02 02 08 00 00   (Bulk)
fixed:    ... 07 05 02 03 08 00 0A   (Interrupt, interval 10 ms)
```

### Requirements

- **System Integrity Protection (SIP) disabled.** The kext can't carry Apple's kext-signing signature (only Apple issues those certificates), and macOS loads unsigned kexts only with SIP off.
  - Shut down.
  - Hold the power button until "Loading startup options" appears, then choose Options.
  - In Recovery, choose Utilities, then Terminal, and run `csrutil disable`.
  - Restart.
  - Check with `csrutil status`.
- The DM2 MIDI driver (`DM2USBMIDIDriver.plugin`) installed in `/Library/Audio/MIDI Drivers/`.

### Install

The commands below run from the repository folder. If you downloaded the release zip, `DM2LEDFix.kext` is at the top level of the zip, so `cd` into the unzipped folder and use `DM2LEDFix.kext` in place of `"DM2 LED Fix/Kext/DM2LEDFix.kext"`.

```
sudo cp -R "DM2 LED Fix/Kext/DM2LEDFix.kext" /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/DM2LEDFix.kext
sudo chmod -R 755 /Library/Extensions/DM2LEDFix.kext
sudo kmutil load -p /Library/Extensions/DM2LEDFix.kext
```

On the test machine this loaded immediately, with no approval prompt and no restart. Then unplug and replug the DM2.

### Check it worked

- Open any MIDI app, for example Audio MIDI Setup. The driver runs inside `MIDIServer`, which only starts when a MIDI app is open.
- Plug in the DM2. The LEDs should blink 5 times, then pads should light when pressed.
- The diagnostic tool gives a detailed check:
  - Command: `sudo Tools/dm2-led-probe/run_probe.sh --capture`
  - Step [2] should show `addr=0x02 OUT Interrupt`.
  - Step [6] should show the driver-path writes succeeding.
- Note: `kUSBDescriptorOverride` does **not** appear as a property on the device in `ioreg`, even when the fix is working. Its absence is not a failure sign.

### Uninstall

```
sudo rm -rf /Library/Extensions/DM2LEDFix.kext
```
Then restart. To turn SIP back on, run `csrutil enable` from Recovery.

---

## 2. Who controls the LEDs

The driver has a per-bank setting that decides what changes the LEDs:

| Value | Pad press changes its LED | MIDI from an app changes the LED |
|---|---|---|
| `Driver Only` (default) | yes | no |
| `MIDI Messages Only` | no | yes |
| `Driver & MIDI Messages` | yes | yes |

For app-defined behavior (latching, momentary, status lights), use **`MIDI Messages Only`**. With `Driver & MIDI Messages`, the driver and your app would both flip the same LED on every press.

Set it from Terminal:

```
defaults write com.joemattiello.driver.dm2 bank1WhoControlsLEDs "MIDI Messages Only"
```

Then replug the DM2; the driver re-reads its settings when the device attaches. Section 6 shows how an app can apply settings without a replug.

---

## 3. The MIDI protocol

In Audio MIDI Setup, the DM2 appears as device **"DM2"** by **"MixMan"**. Everything below is on **MIDI channel 1**.

### Pads to your app (DM2 MIDI source)

| Pad event | Message |
|---|---|
| pressed | Note On, note N, velocity 127 (`90 N 7F`) |
| released | Note Off, note N (`80 N 7F`) |

This is the default, non-sticky behavior. With sticky buttons on (section 7), a press alternates between sending Note On and Note Off.

### Your app to the LEDs (DM2 MIDI destination)

| Message | LED |
|---|---|
| Note On, note N, velocity 1 to 127 | on |
| Note Off, note N | off |
| Note On, note N, velocity 0 | off |

The LED for a pad uses **the same note number the pad sends**.

### Note numbers

Each bank uses 16 notes: bank 1 is notes 0 to 15, bank 2 is 16 to 31, bank 3 is 32 to 47, bank 4 is 48 to 63. Within a bank:

| Note (bank 1) | Pad (as named in the driver source) |
|---|---|
| 0 to 7 | right ring buttons 8 down to 1 (note 0 = right 8, note 7 = right 1) |
| 8 to 15 | left ring buttons 8 down to 1 (note 8 = left 8, note 15 = left 1) |

The driver's own comments say the physical order runs counter-clockwise. The simplest way to label your pads is to press each one and watch which note arrives, for example in a MIDI monitor.

Which banks exist depends on the driver's software mode (section 7). In the default `Generic MIDI` mode there is only bank 1 (notes 0 to 15).

---

## 4. Recipe: latching and momentary pads

Goal: some pads act as **latching** switches, where one press turns the LED on and the function ON, and the next press turns both off. Other pads act as **momentary** switches, lit only while held.

1. Set `bank1WhoControlsLEDs` to `MIDI Messages Only` (section 2).
2. In your app, keep a table of pad number, mode, and current state.
3. React to pad messages:

| Pad event | Latching pad | Momentary pad |
|---|---|---|
| pressed (Note On) | Flip the state. Send LED on if now ON, off if now OFF. Run the ON or OFF action. | Send LED on. Start the action. |
| released (Note Off) | Ignore it. The LED keeps showing the state. | Send LED off. Stop the action. |

Swift sketch using CoreMIDI. The logic is shown; creating the MIDI client and ports and finding the "DM2" source and destination are left out. This sketch has not been compiled.

```swift
enum PadMode { case latching, momentary }

var modes = [UInt8: PadMode]()   // e.g. modes[0] = .latching; modes[1] = .momentary
var isOn  = [UInt8: Bool]()

// Send a 3-byte message to the DM2's MIDI destination (implementation depends on your CoreMIDI setup).
func sendToDM2(_ bytes: [UInt8]) { /* MIDISend / MIDISendEventList to the DM2 destination */ }

func setLED(_ pad: UInt8, _ on: Bool) {
    sendToDM2([on ? 0x90 : 0x80, pad, on ? 127 : 0])
}

// Call this for every message received from the DM2's MIDI source.
func handleFromDM2(status: UInt8, note: UInt8, velocity: UInt8) {
    let pressed = (status & 0xF0) == 0x90 && velocity > 0
    switch modes[note] ?? .momentary {
    case .latching:
        guard pressed else { return }            // releases do nothing for latching pads
        let newState = !(isOn[note] ?? false)
        isOn[note] = newState
        setLED(note, newState)
        // perform the ON or OFF action here
    case .momentary:
        setLED(note, pressed)                    // lit only while held
        // start the action on press, stop it on release
    }
}

// When your app starts, and whenever the DM2 is (re)connected, resend every latching pad's LED,
// because the driver clears all LEDs when the device attaches.
func restoreLEDs() {
    for (pad, mode) in modes where mode == .latching {
        setLED(pad, isOn[pad] ?? false)
    }
}
```

The same pattern covers other ideas: an LED showing a status your app computes, blinking on a timer, or a pad lighting a different pad's LED. They are all Note On and Note Off messages your app sends when it chooses.

---

## 5. Things to know

- **The app owns the state.** The driver clears all LEDs when the DM2 attaches, for example after a replug, sleep, or MIDIServer restart. An app with latching pads should resend its LED state when it sees the DM2 appear, for example through a CoreMIDI setup-changed notification.
- **MIDIServer must be running.** The driver only runs while some MIDI app is open. With no MIDI app open, the DM2 does nothing, not even the startup blink.
- **One LED packet covers all 16 LEDs.** The driver sends the whole bank's LED state on every change. Your app doesn't need to worry about this, but very high message rates (hundreds per second) will send that many USB packets.
- **Only the current bank is shown.** In banked mode, notes for a bank that isn't selected update that bank's stored state. It becomes visible when the user switches to that bank.

---

## 6. Changing settings from an app

The settings live in the preferences domain `com.joemattiello.driver.dm2` of the user running MIDIServer, which is the logged-in user. An app that isn't sandboxed can write them and tell the running driver to reload them without a replug:

```swift
let domain = "com.joemattiello.driver.dm2" as CFString
CFPreferencesSetAppValue("bank1WhoControlsLEDs" as CFString, "MIDI Messages Only" as CFString, domain)
CFPreferencesAppSynchronize(domain)

DistributedNotificationCenter.default().postNotificationName(
    NSNotification.Name("Preferences Changed"),
    object: "com.joemattiello.driver.dm2",
    userInfo: nil,
    deliverImmediately: true)
```

The driver also listens for these other notification names, all using the same `object`:

| Notification name | Effect |
|---|---|
| `Preferences Changed` | re-read all settings |
| `Clear All LEDs` | turn off every LED in every bank |
| `Reset Calibration` | reset the slider and crossfader calibration |
| `Reset Interface` | re-initialise the USB interface |

---

## 7. Other LED-related settings

All of these use the `com.joemattiello.driver.dm2` domain. Replace `bank1` with `bank2`, `bank3` or `bank4` for the other banks, in banked mode.

| Key | Type | Effect |
|---|---|---|
| `softwareMode` | string | `Generic MIDI` (default, one bank; the 4 bottom buttons send notes), `Generic MIDI with Banks` (the 4 bottom buttons switch between banks 1 to 4), `Mixxx`, `Traktor` |
| `bank1WhoControlsLEDs` | string | see section 2 |
| `bank1StickyButtons` | bool | the driver makes every pad in the bank latch. A press alternates between sending Note On and Note Off, and the LED follows. This covers all pads or none; for a mix, use the app approach in section 4. |
| `bank1InvertLeds` | bool | flips the meaning of on and off for the bank (banked modes) |
| `bank1DisplaysMIDIClock` | bool | the bank's LEDs show a running light driven by incoming MIDI clock; note messages to that bank are ignored |
| `midiClockResolution` | string | `16th` (default), `1/4` or other values, for the MIDI clock display |

Example: `defaults write com.joemattiello.driver.dm2 bank1StickyButtons -bool true`

---

## 8. For developers and agents

- LED fix kext: `DM2 LED Fix/Kext/DM2LEDFix.kext/Contents/Info.plist`. The corrected descriptor is stored base64-encoded in `kUSBDescriptorOverride.descriptor`.
- DriverKit version of the same fix (needs a paid Apple Developer team to sign; not in use): `DM2 LED Fix/` (`project.yml`, `App/`, `Driver/`).
- LED packet format: 4 bytes to endpoint 0x02 (driver pipe index 2).
  - Bytes 0 and 1 hold the 16 LED bits (inverted).
  - Bytes 2 and 3 are `FF FF`.
  - See `MIDI Driver/DM2USBMIDIDriver/DM2USBMIDI.cpp`: `sendLights` and `StartInterface`.
- MIDI-in to LED handling: `DM2USBMIDI.cpp` `PrepareOutput` (note on/off parsing) and `Configurations/DM2Configuration.cpp` `buttonReceived` and `toggleLED` (note to LED mapping).
- Pad to LED handling: `DM2USBMIDI.cpp` `HandleInput` and `DM2Configuration.cpp` `button*Clicked` / `makeBasicNote`.
- Settings: `DM2USBMIDI.cpp` `readSettings`, `Configurations/DM2Configuration.cpp` and `Configurations/DM2BasicBanks.cpp` `readSettings`.
- Investigation history, and approaches that failed and must not be retried: `AGENT_NOTES.md`.
