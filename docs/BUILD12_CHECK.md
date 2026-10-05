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

## Extended passive observation

A later review found 129 matching fullscreen reports spanning about four minutes. Mean received FPS was 59.984 and drawing FPS 59.799; both medians were approximately 60. Mean GPU execution was 0.560 ms and mean app frame age 0.484 ms. No late capture drops were reported. This observation includes fullscreen transition and interactive desktop use, so it is not an uninterrupted controlled benchmark.

Five two-second reports showed drawing FPS below 59, including a 46.62 FPS transition report; another interval had a maximum capture gap of 74.69 ms. Zero reported capture drops does not imply perfectly regular delivery or presentation. These outliers require controlled follow-up before claiming sustained pacing or performance preservation. The observations do not identify whether the cause was the card, desktop interaction, app scheduling or background load.

## Expanded graphics regression checks

The repository's graphics tests were extended without changing the capture, rendering or audio path. The installed app was left running. The locally built test executable passed 32 color/range checks across 720p, 1080p, 1440p and 4K, and 16 orientation/black-bar checks across native, tall and wide render targets. Fixed eight-bit limited-range vectors check black, white, red, green, blue, middle gray and below/above-range clipping against RGB expectations with a three-code-value tolerance. The intended color model is [ITU-R BT.709](https://www.itu.int/rec/R-REC-BT.709-6-201506-I/en).

A separate temporary executable with intentionally swapped chroma channels failed the new red-reference test, returning exit code 1 with the expected/actual pixel values. The earlier neutral black/white tests would not detect that fault. Test failures now report an error and exit rather than escaping as an unhandled Swift error. The original shader and rendering path were not changed by these test additions.

These are offscreen synthetic tests of the actual encoder. They do not certify the Xbox's output settings, the card's conversion, macOS display management, panel calibration, live tearing or sustained hardware capture. The expanded test code has not replaced the installed executable; doing so solely for test additions would unnecessarily change its local signature and capture permissions.
