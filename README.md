# DM2 macOS MIDI Driver (ARM64 Port)

A CoreMIDI driver for the **MixMan DM2** USB DJ controller, ported to build and run on modern macOS (Apple Silicon + Intel).

![DM2 MIDI Output](MIDI%20Driver/DM2_OSX_MIDI_Driver_preview.png)

## Background

The MixMan DM2 is a USB DJ controller (Vendor ID `0x0665`, Product ID `0x0301`) that uses a vendor-specific USB protocol rather than the standard USB-MIDI class. It requires a custom CoreMIDI driver to translate its raw USB packets into standard MIDI messages.

This project is a port of [joematt/dm2usbmididriver](https://github.com/joematt/dm2usbmididriver) (last updated 2010) to compile and run on macOS 14+ with Xcode 16 as a Universal Binary (arm64 + x86_64).

## Features

- Full MIDI input from all DM2 controls: buttons, jog wheels, joystick, and slider
- Multiple configuration modes (Generic, Traktor, Mixxx)
- Bank switching for expanded MIDI mappings
- Joystick auto-calibration
- Builds as Universal Binary (Apple Silicon + Intel)

## Known Limitations

**LED output does not work on Apple Silicon Macs.** The DM2 firmware declares its LED output endpoint as USB Bulk, but the device is low-speed USB (1.5 Mb/s). The USB spec prohibits bulk transfers on low-speed devices, and the xHCI controller on Apple Silicon correctly rejects them. Linux and Windows work around this at the kernel level, but no user-space macOS workaround exists. MIDI input is fully functional regardless.

## Building

1. Open `MIDI Driver/DM2USBMIDIDriver.xcodeproj` in Xcode 16+
2. Build (Cmd+B) — produces a Universal Binary `.plugin` bundle

## Installation

1. Copy the built plugin to the MIDI Drivers directory:
   ```
   sudo cp -R "build/Release/DM2USBMIDIDriver.plugin" "/Library/Audio/MIDI Drivers/"
   ```
2. Restart the MIDI server:
   ```
   sudo killall MIDIServer
   ```
3. Plug in the DM2 — it should appear in Audio MIDI Setup.app

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
```

## Changes from Original

- Removed Growl framework dependency (notifications)
- Replaced `Carbon/Carbon.h` and `CoreServices/CoreServices.h` with `CoreFoundation/CoreFoundation.h`
- Removed x86-only `__attribute__((fastcall))`
- Replaced deprecated `IOMasterPort` with `IOMainPort`
- Replaced deprecated `NSLookupAndBindSymbolWithHint` with `dlsym`
- Added `CAMutex.h` and `CAHostTimeBase.h` (minimal replacements for Apple CoreAudio utility classes)
- Fixed `USBInterface::Open()` missing `mIsOpen = true` assignment
- Added `SetAlternateInterface(0)` call for proper pipe table initialization on modern macOS
- Resolved SVN merge conflicts in `MIDIDriverClass.h` and `USBMIDIDriverBase.cpp`
- Fixed `strlen()` on binary LED buffers (changed to fixed size `4`)
- Fixed char narrowing warnings
- Added null guards for robustness

## Credits

- Original driver by [Joe Mattiello](https://github.com/joematt)
- Based on Apple's USB MIDI driver sample code
- ARM64 port assisted by Claude (Anthropic)

## License

The shared USB/MIDI framework files are covered by the Apple sample code license (see file headers). The DM2-specific driver code is from the original open-source project.
