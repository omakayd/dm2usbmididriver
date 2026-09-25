# DM2 macOS Generic MIDI Driver Handover Brief

_Last updated: 2026-09-24. Source of truth: README.md, LED_CONTROL.md, AGENT_NOTES.md, and the code._

## Mission

A CoreMIDI driver for the **MixMan DM2** USB DJ controller, ported to build and run on modern macOS (Apple Silicon + Intel), with working LED output.

## Status

- MIDI input: works (v1.0.0).
- LED output: works on Apple Silicon (M5, macOS 26.5.2) via `DM2 LED Fix/Kext/DM2LEDFix.kext`, a codeless kext that uses
  `AppleUSBHostMergeProperties` + `kUSBDescriptorOverride` to re-declare EP 0x02 as Interrupt. Requires SIP disabled.
  User-confirmed (5-blink at attach, pads toggle LEDs). Released as v1.1.0.
- Random pads lit at attach: fixed (`haveBaseline` in DM2USBMIDI.cpp), user-confirmed.
- MIDI-controlled LED mode (`bank<N>WhoControlsLEDs`): documented from code in LED_CONTROL.md, NOT yet hardware-tested.
- DriverKit version of the fix (`DM2 LED Fix/App`, `Driver`, `project.yml`): blocked, needs a PAID Apple team.
  Personal teams cannot get DriverKit / System Extension profiles, and AMFI kills it even with SIP off.

## Key facts

- Language: C++, Obj-C
- Repo: https://github.com/omakayd/dm2usbmididriver.git (PUBLIC, yours, omakayd; origin push OK after you test).
  Public repo: never commit names, team IDs, emails, or local paths.
- DM2: low-speed USB, VID 0x0665, PID 0x0301. EP 0x81 interrupt IN (8-byte reports), EP 0x02 LED OUT (4-byte packets).
- MIDIServer (which hosts the driver) only runs while a CoreMIDI client app is open. No app open means no blink.

## Start here

1. `AGENT_NOTES.md`: newest-first findings, including closed routes that must not be retried.
2. `LED_CONTROL.md`: kext install, LED protocol, settings keys, notifications.
3. `README.md`: build, install, structure.
4. `Tools/dm2-led-probe/`: diagnostic (`sudo ./run_probe.sh --capture`); step [2] config raw bytes prove the fix.

## Build

```
cd "MIDI Driver" && xcodebuild -project DM2USBMIDIDriver.xcodeproj -target DM2USBMIDIDriver -configuration Release SYMROOT="$PWD/build.noindex" OBJROOT="$PWD/build.noindex/obj" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=11.0 build
```
Verify: `lipo -info`, `otool -l -arch arm64|x86_64` minos 11.0, `codesign -v`.

## Applicable standing rules

Universal rules load via the router `CLAUDE.md` at the Claude umbrella root (style, safety, build hygiene, no-push-before-test). This is a utility/app project, not a reverse-engineering port: the RE manual does not apply.
