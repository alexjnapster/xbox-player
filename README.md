# Xbox Player for Mac

A native, local Mac player for HDMI console video arriving through a USB capture card. It uses AVFoundation, Metal and the newest available frame, with card audio played through the Mac's default output.

## What it supports

- Highest advertised capture frame rate at 1080p or 720p; 1440p mode when available.
- Genuine 3840×2160 at 60/59.94 FPS only when a connected card exposes that capture mode to macOS. No 4K30 substitution or relabeling of upscaled video.
- Native-resolution rendering, aspect-preserving windowed/fullscreen scaling, and optional frame-arrival Fast Preview.
- Capture-card selection, volume/mute, saved preferences, pause/reconnect, feed-health status, and bounded local diagnostics.

UGREEN 15389/CM629 was observed exposing 1080p60 and 1440p30, with no 4K capture or 1080p120. HDMI input capability is different from USB capture capability. This is an 8-bit SDR player; HDR tone mapping, recording and broadcasting are not implemented.

## Build

Requires macOS 14 or newer and Apple's Command Line Tools (`xcode-select --install`). Build for the current Mac architecture:

```sh
./scripts/build.sh
```

The app and a ZIP are created in `build/`. To install the built app in `/Applications`, quit any running Xbox Player and use:

```sh
./scripts/build.sh --install
```

Builds use a local ad-hoc signature. They are not Apple notarized releases. The build stages signing outside the repository to avoid Finder/iCloud metadata interfering with app signing. macOS Camera permission is used for card video, and Microphone permission for card audio. A rebuild changes the local signature, so macOS may request these permissions again; see the known limits for stale grants.

## Tests

```sh
./scripts/test.sh
```

Mode selection tests cover highest-FPS priority, fractional/fixed timing, pixel-format preference and unsupported 4K60 rejection. GPU tests exercise the actual NV12 encoder with black/white reference frames at 720p, 1080p, 1440p and 4K. Rendering tests require a working Metal device. They do not certify real 4K60 streaming.

## Controls

| Action | Shortcut |
| --- | --- |
| Fullscreen | Control–Command–F |
| Mute / unmute | Command–M |
| Pause capture and release card | Command–D |
| Resume / reconnect | Command–R |
| Card capabilities | Command–I |
| Performance statistics | Command–P |
| Show / hide controls | Shift–Command–H |
| Experimental Fast Preview | Command–E |
| Quit | Command–Q |

Quit OBS or pause its capture before using the same card in Xbox Player. Sound follows the Mac's selected output. Fast Preview disables Metal-layer display synchronization and can affect tearing/pacing; it is optional and saved.

## Measurements and privacy

Capture FPS counts delivered frames, including identical images. Drawing FPS is not the Xbox game's engine FPS. GPU execution and frame age inside the app exclude card buffering and display/compositor timing; they are not controller-to-screen latency. Short 1080p60 gameplay measurements showed approximately 60 FPS; the user reported working sound and good picture but similar controller delay. No zero-lag claim is made.

Diagnostics are local in `~/Library/Application Support/Xbox Player/`: `Last Session.json` and a bounded `Performance.jsonl` timing/status log. The app does not record video/audio, transmit diagnostics, or provide network services. Do not post your private logs without reviewing them.

## Quality and remaining work

[100-point acceptance criteria](docs/QUALITY_CRITERIA.md), [Xbox settings](docs/XBOX_SETTINGS.md), [research](docs/RESEARCH.md), [HDMI-CEC feasibility](docs/CEC.md), and [known limits](docs/KNOWN_LIMITS.md).

HDMI-CEC control is not implemented. This UGREEN card has no verified host CEC control path; a documented USB-CEC adapter and real Xbox/topology tests would be needed for a supported integration. CEC can provide device-control convenience but does not reduce capture latency.

The scorecard is a target, not a certified current score. Physical recovery, long soak, calibrated color, VoiceOver and controller-to-screen timing need the listed checks. Reports must distinguish tested results from hardware-conditional support.

## License

No open-source license has been selected. Publishing the source does not grant a general license to reuse it; GitHub's normal viewing/forking terms still apply. A separate license can be added by the owner later.
