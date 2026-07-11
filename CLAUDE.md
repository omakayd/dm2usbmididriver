# DM2 macOS Generic MIDI Driver Handover Brief

_Last updated: 2026-07-11. Source of truth: README.md + code._

## Mission

A CoreMIDI driver for the **MixMan DM2** USB DJ controller, ported to build and run on modern macOS (Apple Silicon + Intel).

## Key facts

- Language: C++, Obj-C
- Repo: https://github.com/omakayd/dm2usbmididriver.git (yours, omakayd; origin push OK after you test)
- Last commit: 2026-02-23 23:54:04 -0600  Port DM2 USB MIDI driver to ARM64 macOS

## Start here

1. Read `README.md` (the source of truth for this project).
2. This is a small standalone utility with no separate `_research/` ledger; the code and README are authoritative.

## Applicable standing rules

Universal rules load via the router `CLAUDE.md` at the Claude umbrella root (style, safety, build hygiene, no-push-before-test). This is a utility/app project, not a reverse-engineering port: the RE manual does not apply.
