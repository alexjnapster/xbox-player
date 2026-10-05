# Known limits and validation status

This repository does not claim that every possible error has been eliminated.

- Current UGREEN card: 1080p60 and 1440p30 capture. 4K60 requires a different compatible capture device; no sustained 4K60 hardware test has been run.
- 8-bit SDR NV12 only. HDR transfer functions and tone mapping are not implemented.
- Native fullscreen/control preferences and pause/resume recovery were checked in build 11. Build 12 adds further error handling; its live validation is in progress while macOS capture permissions are renewed. No performance-preservation certification is claimed for build 12 yet.
- Physical unplug/replug, eight-hour soak, calibrated color/reference patterns, comprehensive VoiceOver use and controller-to-screen latency remain unverified.
- A card can deliver repeated or black frames while HDMI is absent. The watchdog detects missing frame delivery, not every HDMI signal loss.
- Output-device changes and audio/video drift require hardware listening checks.
- Local signatures are ad-hoc, not notarized. A rebuilt executable changes its designated code requirement, which can invalidate earlier Camera/Microphone grants. macOS may need fresh permission approval even when an old entry looks enabled. Do not edit the privacy database or broaden signing requirements to bypass this protection.
- Source currently builds in Swift 5 language mode. Strict Swift 6 concurrency checks report isolation warnings; a Swift 6 migration is not complete. Current capture and timing state uses serial queues and locks, but this is not a comprehensive thread-sanitizer certification.

## Bugs addressed

- Startup crash from a menu item accessed before initialization.
- Potential open capture-session transaction if device-input creation throws.
- Capture/audio sessions left running after a later video setup failure.
- Old measurements displayed after pausing/reconnecting.
- Old picture left visible when automatic drawing is paused and the card stops.
- Audio status erased by periodic FPS text.
- Invalid saved mode reselected after capability fallback.
- Wall-clock adjustments affecting duration measurements; intervals now use monotonic time.
- Nontransitive frame-rate near-tie ordering that could prefer a lower rate; strict highest-FPS ordering and boundary/permutation tests were added.
- Volume changes during connection being overwritten by an earlier volume snapshot; current volume is reapplied on the capture queue after connection.
- Failure to check Metal queue/cache creation and capture-session startup results.
- Camera denial unnecessarily requesting Microphone access; Camera access is now checked first.
- Missing connection-phase diagnostics and a warning for prolonged connection.

## Issue reports

Include macOS version, Mac/chip, card model, selected mode, preview mode, display refresh and reproduction steps. Review logs before posting; do not include captured personal content, device identifiers, credentials or private details.
