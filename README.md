# DM2 macOS MIDI Driver (ARM64 Port)

A CoreMIDI driver for the **MixMan DM2** USB DJ controller, ported to build and run on modern macOS (Apple Silicon + Intel).

![DM2 MIDI Output](MIDI%20Driver/DM2_OSX_MIDI_Driver_preview.png)

## Background

The MixMan DM2 is a USB DJ controller (Vendor ID `0x0665`, Product ID `0x0301`) that uses a vendor-specific USB protocol rather than the standard USB-MIDI class. It requires a custom CoreMIDI driver to translate its raw USB packets into standard MIDI messages.

This project is a port of [joematt/dm2usbmididriver](https://github.com/joematt/dm2usbmididriver) (last updated 2010) to compile and run on macOS 14+ with Xcode 16 as a Universal Binary (arm64 + x86_64).

## Features

- Full MIDI input from all DM2 controls: buttons, jog wheels, joystick, and slider
- LED output on current macOS, including Apple Silicon (needs the one-time LED fix below)
- LEDs can be driven by the driver, by MIDI from your own app, or both (see [LED_CONTROL.md](LED_CONTROL.md))
- **DM2 Settings**, a settings app for every driver option, with changes applied live
- Multiple configuration modes (Generic, Traktor, Mixxx)
- Bank switching for expanded MIDI mappings
- Joystick auto-calibration
- Universal Binary (Apple Silicon + Intel), macOS 11.0 or later

## LED output on modern macOS

The DM2 firmware declares its LED output endpoint (0x02) as USB Bulk, but the device is low-speed USB (1.5 Mb/s), where Bulk endpoints are not allowed. Current macOS rejects that endpoint in software (`IOUSBHostFamily::validateEndpointMaxPacketSize ... endpoint 0x02 invalid wMaxPacketSize`), so without help the LED pipe is never created. MIDI input works either way.

`DM2 LED Fix/Kext/DM2LEDFix.kext` fixes this. It is a codeless kernel extension (a settings file, no program code) that uses Apple's own `AppleUSBHostMergeProperties` class and `kUSBDescriptorOverride` to give macOS a corrected descriptor with endpoint 0x02 declared as Interrupt, which is legal at low speed and works the same for the DM2.

**It requires System Integrity Protection (SIP) to be disabled**, because only Apple can issue the certificate that signs kexts for loading with SIP on. Full steps, verification, and uninstall are in [LED_CONTROL.md](LED_CONTROL.md#1-enabling-leds-on-a-modern-mac-one-time-setup).

`DM2 LED Fix/` also contains a DriverKit version of the same fix (host app plus dext) that would work with SIP on. It is unused because building it needs a paid Apple Developer team with DriverKit entitlements; see [AGENT_NOTES.md](AGENT_NOTES.md) for details.

## Building

From the command line (universal, macOS 11.0 minimum):

```
cd "MIDI Driver"
xcodebuild -project DM2USBMIDIDriver.xcodeproj -target DM2USBMIDIDriver -configuration Release \
  SYMROOT="$PWD/build.noindex" OBJROOT="$PWD/build.noindex/obj" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=11.0 build
```

The plugin is written to `MIDI Driver/build.noindex/Release/DM2USBMIDIDriver.plugin`. Opening the project in Xcode and building also works.

The settings app builds with the command line tools alone (no Xcode project):

```
"DM2 Settings/build.sh"
```

It writes a universal, ad-hoc signed `DM2 Settings/build.noindex/DM2 Settings.app`.

## Installation

Prebuilt copies of the driver, the LED fix and the settings app are attached to each [GitHub release](https://github.com/omakayd/dm2usbmididriver/releases).

1. Copy the plugin to the MIDI Drivers directory:
   ```
   sudo cp -R DM2USBMIDIDriver.plugin "/Library/Audio/MIDI Drivers/"
   ```
2. Restart the MIDI server:
   ```
   sudo killall MIDIServer
   ```
3. For LEDs, install `DM2LEDFix.kext` as described in [LED_CONTROL.md](LED_CONTROL.md#1-enabling-leds-on-a-modern-mac-one-time-setup).
4. Copy `DM2 Settings.app` to `/Applications`. It is not notarized, so the first time, right-click it and choose Open.
5. Open a MIDI app (DM2 Settings counts) and plug in the DM2. It appears as a MIDI device, and with the LED fix installed the LEDs blink 5 times at attach.

The driver runs inside `MIDIServer`, which macOS starts only while a MIDI app is open. With no MIDI app running, the DM2 is not configured and the LEDs stay dark.

## Settings app

**DM2 Settings** changes every driver option without Terminal:

- Status: whether the driver and the LED fix are installed, and whether the DM2 is connected and running.
- Software mode: Generic MIDI, Generic MIDI with 4 Banks, Mixxx or Traktor.
- Pads and LEDs, per bank: who controls the LEDs (pad presses, MIDI from apps, or both), sticky (latching) buttons, inverted LEDs, MIDI clock display, and a scratch ring filter that ignores small bumps.
- MIDI clock display resolution: 16th notes, 32nd notes, or quarter notes only.
- Clear LEDs, Reset Joystick Calibration, Reset Interface, and Restore Defaults.

Changes apply immediately while the DM2 is connected, with no replug. The app also keeps the MIDI server running while it is open, so the DM2 works with the app as its only MIDI client.

## Controlling the LEDs from your own app

By default the driver toggles each pad's LED when the pad is pressed. The `bank<N>WhoControlsLEDs` setting hands the LEDs to MIDI instead: send Note On to light a pad and Note Off to clear it, on the same note number the pad sends. That lets an app show latching and momentary pads differently, mirror its own state, and so on. Set "LEDs follow" to *MIDI from apps* in DM2 Settings to turn it on. [LED_CONTROL.md](LED_CONTROL.md) has the full protocol, note table, a Swift example, and how to change the settings from code.

## Diagnostics

`Tools/dm2-led-probe/` is a command-line probe that reports what macOS does with the DM2's endpoints and tries every LED write path. Run `sudo Tools/dm2-led-probe/run_probe.sh --capture` with the DM2 plugged in; see its [README](Tools/dm2-led-probe/README.md).

## Project Structure

```
MIDI Driver/
  DM2USBMIDIDriver/           # DM2-specific driver code
    DM2USBMIDI.cpp/h          # Main driver: USB packet parsing, MIDI output
    DM2 Structs.h             # DM2 hardware status structures
    Configurations/            # MIDI mapping configurations
      DM2Configuration.cpp/h   # Base configuration class
      DM2BasicBanks.cpp/h      # Generic config with bank switching
      Traktor/                 # Traktor-specific mappings
      Mixxx/                   # Mixxx-specific mappings
  Shared/                      # Reusable CoreMIDI/USB driver framework
    USBDevice.cpp/h            # IOKit USB device/interface abstraction
    USBMIDIDevice.cpp/h        # USB MIDI device with async I/O
    USBMIDIDriverBase.cpp/h    # CoreMIDI driver base class
    USBVendorMIDIDriver.cpp/h  # Vendor-specific driver base
    MIDIDriver.cpp             # CFPlugIn COM interface glue
    CAMutex.h                  # pthread_mutex RAII wrapper
    CAHostTimeBase.h           # mach_absolute_time utilities
  DM2USBMIDIDriver.xcodeproj   # Xcode project
DM2 LED Fix/
  Kext/DM2LEDFix.kext          # Codeless kext: descriptor override that enables the LEDs
  App/, Driver/, project.yml   # DriverKit version of the same fix (needs a paid team)
DM2 Settings/                  # SwiftUI settings app
  Sources/                     # DriverSettings (preferences), DeviceStatus, the window
  build.sh                     # Universal build and ad-hoc signing
Tools/dm2-led-probe/           # USB endpoint diagnostic tool
LED_CONTROL.md                 # LED setup and app control guide
AGENT_NOTES.md                 # Development log and findings
```

## Changes from Original

- Removed Growl framework dependency (notifications)
- Replaced `Carbon/Carbon.h` and `CoreServices/CoreServices.h` with `CoreFoundation/CoreFoundation.h`
- Removed x86-only `__attribute__((fastcall))`
- Uses `IOMainPort` on macOS 12+ and `IOMasterPort` on macOS 11
- Replaced deprecated `NSLookupAndBindSymbolWithHint` with `dlsym`
- Added `CAMutex.h` and `CAHostTimeBase.h` (minimal replacements for Apple CoreAudio utility classes)
- Fixed `USBInterface::Open()` missing `mIsOpen = true` assignment
- Added `SetAlternateInterface(0)` call for proper pipe table initialization on modern macOS
- Resolved SVN merge conflicts in `MIDIDriverClass.h` and `USBMIDIDriverBase.cpp`
- Fixed `strlen()` on binary LED buffers (changed to fixed size `4`)
- Fixed char narrowing warnings
- Added null guards for robustness
- LED state is cleared at attach, and the first input report is used as a baseline, so pads no longer come up randomly lit
- Added the `DM2LEDFix.kext` descriptor override that makes the LED endpoint usable on current macOS
- In MIDI LED mode, Note On now lights a pad and Note Off turns it off (the LED bits are active-low, and the check was reversed)
- Settings for all four banks are read, not only bank 1, and each setting is type-checked, so a wrong type falls back to the default
- Fixed a use-after-free of `midiClockResolution` and a leak of `softwareMode` when settings are re-read
- Removed undefined behavior in the no-banks modes (deleting uninitialized pointers)
- Added the DM2 Settings app

## Credits

- Original driver by [Joe Mattiello](https://github.com/joematt)
- Based on Apple's USB MIDI driver sample code
- ARM64 port assisted by Claude (Anthropic)

## License

The shared USB/MIDI framework files are covered by the Apple sample code license (see file headers). The DM2-specific driver code is from the original open-source project.
