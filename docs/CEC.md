# HDMI-CEC: feasibility and acceptance requirements

Checked 5 October 2026. CEC control is not implemented in Xbox Player. It is an optional console/device-control feature; it does not accelerate USB video capture or substitute for a gaming controller.

## Current setup

The connected UGREEN 15389 exposes USB video-control/video-streaming interfaces, audio-control/audio-streaming interfaces, and a vendor-specific HID interface. That HID interface uses usage page 0xFF00 and advertises an eight-byte feature report. This establishes that a vendor control channel exists; it does **not** identify its commands or prove access to the HDMI CEC wire. No undocumented reports were sent to the card.

UGREEN's [15389 product specification](https://www.ugreenindia.com/products/ugreen-hdmi-video-capture-card-4k-input-2k-30hz-1080p-60fps-usb-a-usb-c-15389) advertises video/audio capture, but does not document host CEC control. UGREEN is not in the [libCEC supported-hardware list](https://github.com/Pulse-Eight/libcec#supported-hardware). No supported USB-CEC adapter or installed `cec-client` was identified in this setup. These observations establish **no verified CEC control path**, rather than proving that the chip could never support one.

The Mac's Studio Display is connected through Thunderbolt. It is not an HDMI TV to target with CEC TV power/input commands. Player volume and the Mac's audio output remain separate from HDMI receiver volume.

## Viable hardware path, pending a real test

A dedicated USB-CEC adapter gives the Mac a documented connection to the HDMI control bus. Pulse-Eight provides one supported by libCEC. Its [current manual](https://support.pulse-eight.com/support/solutions/articles/30000048842-usb-cec-adapter-user-manual) lists TV power/input, remote commands and AV-receiver control, and an inline video limit of 4K60, with no 4K120 passthrough. Its macOS support is through community packaging, not direct vendor support.

Candidate wiring is Xbox → USB-CEC adapter → UGREEN HDMI input, with both USB devices connected to the Mac. This topology is **unverified**. Discovery must establish a usable HDMI physical address and the Xbox's logical address; a capture-card sink may behave differently from a TV. An adapter purchase alone does not establish working Xbox control. Confirm the actual Xbox model, its CEC settings, device responses and the HDMI topology before advertising compatibility.

libCEC has [macOS build instructions](https://github.com/Pulse-Eight/libcec/blob/master/docs/README.osx.md), but their listed historical OS tests do not certify the current Apple Silicon/macOS combination. A real adapter test on the target Mac remains required. The library is [GPL-2.0-or-later or commercially licensed](https://github.com/Pulse-Eight/libcec/blob/master/LICENSE.md); resolve distribution terms before linking or bundling it. No CEC dependency is currently included in this app.

## Requirements for a worthwhile implementation

- Discover adapters and devices explicitly; distinguish missing backend, missing adapter, unreachable console, unsupported command and working control. Never present an enabled button as evidence of hardware support.
- Offer power status, wake/standby, directional menu navigation, select/back, TV input and receiver volume only for verified target/device capabilities. Xbox support for each command must be tested, not inferred from TV support. Keep gaming on the Xbox controller.
- Address the selected device discovered on the bus. Logical address 0 is the TV, not automatically the Xbox. Separate commands to the console, TV and receiver; avoid bus-wide standby.
- Keep capture/audio rendering independent. Use a separate serialized control worker, bounded timeouts and retries, cancellation on disconnect/quit, and one bounded command queue. Do not probe the bus per frame or block the capture/main queues.
- Pair key-down/key-up messages, including cancellation and disconnect, to prevent stuck navigation. Rate-limit repeats and recover cleanly when the adapter reconnects.
- Make automatic power changes opt-in. Closing or pausing the player must not unexpectedly turn off the console or another household device.
- Preserve local-only operation and bounded diagnostics without publishing device identifiers. Do not send undocumented HID commands or install speculative capture-card firmware/drivers.

## Evidence needed before claiming support

Test discovery, each advertised command, held-key release, timeout, unplug/replug, absent adapter/backend and quit during a command. Verify the console, TV and receiver targets independently where applicable. Capture and audio must remain usable if CEC fails.

Run matched 1080p60 fullscreen tests with CEC disabled, idle and under repeated menu commands, using the performance-preservation gates in [QUALITY_CRITERIA.md](QUALITY_CRITERIA.md). Check timing distributions, drops, listening behavior and adapter passthrough picture quality. CEC is certified only for the tested adapter/console/topology. Its timing is command response, never controller-to-screen gameplay latency.
