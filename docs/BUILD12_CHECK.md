# Build 12: short live check

5 October 2026. Installed build 12 was observed receiving 1920×1080 video through UGREEN 15389, fullscreen with controls hidden and Fast Preview enabled. Ten distinct two-second reports were collected after two warmup reports. The window showed the Xbox dashboard/guide, rather than a controlled moving gameplay sequence.

| Metric | Mean | Median |
| --- | ---: | ---: |
| Received FPS | 60.0113 | 60.0117 |
| App drawing FPS | 59.9613 | 60.0117 |
| GPU execution | 0.5943 ms | 0.4246 ms |
| Frame age inside app | 0.3789 ms | 0.3568 ms |

The drawable was 1920×1080. Reports showed zero late capture drops and an active Xbox audio session. That audio-session status does not establish an audible listening check. The permission wait reported earlier had resolved without bypassing macOS privacy controls.

This is supporting evidence of working startup and fullscreen capture, not a sustained-performance or latency certification. The scene and background load were not matched to earlier baseline gameplay, so differences in timing cannot establish a regression or improvement. Frame delivery may include repeated images; drawing FPS is not game-engine FPS. GPU time and frame age omit capture-card buffering, game/controller delay, compositor timing and display scanout. Longer alternating comparisons, listening and recovery checks remain required by [QUALITY_CRITERIA.md](QUALITY_CRITERIA.md).
