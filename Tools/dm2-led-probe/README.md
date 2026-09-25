# dm2-led-probe

Finds out exactly what macOS does with the DM2's LED endpoint (0x02, declared Bulk OUT on a
low-speed device) and tries to light the LEDs through every user-space path available.

**Result (2026-09, Apple Silicon, macOS 26):** without a fix macOS refuses endpoint 0x02 (outcome one
below). With `DM2LEDFix.kext` installed, step [2] shows `07 05 02 03 08 00 0a` (0x02 as Interrupt),
and steps [4] and [6] succeed and the LEDs blink. Setup is in [LED_CONTROL.md](../../LED_CONTROL.md).

## Run it

1. Plug the DM2 in directly to the Mac (no hub for the first run).
2. If the DM2 driver is NOT installed (current state), run:
   ```
   ./run_probe.sh
   ```
   If the driver IS installed, MIDIServer holds the interface. Either run
   `sudo ./run_probe.sh --capture`, or remove the driver from `/Library/Audio/MIDI Drivers/`
   and restart MIDIServer first.
3. Watch the DM2's LEDs during steps [4] and [6]. When step [5] says so, press or move a control.
4. A `probe-report-<date>.txt` file is written here with the tool output plus the kernel USB log.

Optional second run: repeat through a USB 2.0 hub (different path through the controller).

`./build.sh` rebuilds the binary (universal, macOS 11.0+) if needed.

## What the steps do

| Step | What | API |
|---|---|---|
| [1] | Device speed, location, which drivers are attached | IORegistry |
| [2] | Device and configuration descriptors as macOS sees them | IOUSBHost |
| [3] | Create pipes for 0x81 and 0x02, show the type macOS gave them; retry 0x02 after selecting alt setting 0 | IOUSBHost |
| [4] | Blink the LEDs on 0x02 (6 writes, 4 bytes each, same packet format as the driver) | IOUSBHost |
| [5] | Read one packet from 0x81 to prove the probe itself can talk to the DM2 | IOUSBHost |
| [6] | The driver's own path: pipe table via IOUSBLib, then `WritePipe(pipe index 2)` | IOUSBLib |

## Reading the result

- **[3] 0x02 fails, [6] shows only 1 endpoint:** macOS refuses to create the LED endpoint at all.
  The exact error code in [3] and any kernel log lines are the evidence. This is what current
  macOS does without the fix; install `DM2LEDFix.kext` (see ../../LED_CONTROL.md).
- **[3] 0x02 created as Bulk, [4] writes fail or time out:** the pipe exists but the controller
  rejects the transfers. The kernel log section shows why.
- **[3] 0x02 created as Interrupt:** macOS rewrote the type the way Linux does. [4] should work,
  and the driver needs to write to it with interrupt semantics.
- **[4] writes succeed and the LEDs blink, but [6] fails:** the problem is the driver's path
  (pipe index or API), and the driver can be fixed.
- **[4] and [6] both succeed and the LEDs blink:** LED output works on this Mac; look at the
  driver's startup or packet logic instead.
