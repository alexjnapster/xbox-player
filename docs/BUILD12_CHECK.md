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
