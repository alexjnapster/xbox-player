# Xbox Player: 100-point acceptance criteria

5 October 2026. This is a target and a testable scorecard, not a current score. Scope: playing Xbox locally on the Mac through UGREEN 15389/CM629, prioritizing low delay, preserved performance, working audio and good picture. Public source delivery is also required.

## Scoring rules

Award points only when the stated evidence exists for the installed release. Untested checks remain unverified, not passed. Evidence from an older build must be rerun when affected code changes. A 100/100 assessment requires every applicable check and all release gates. Hardware limits must be disclosed; hiding them, upscaling and calling it 4K capture, or calling capture FPS the game's FPS fails the release gates regardless of numeric score.

The scope includes actual current-card behavior and correct conditional handling of other hardware. End-to-end 4K60 certification remains a separate gate before advertising that hardware configuration as tested. It cannot be inferred from a synthetic shader test.

| Area | Points | Required result and evidence |
| --- | ---: | --- |
| Performance and latency | 30 | 12 points: matched 1080p60 fullscreen tests sustain at least 59.5 received/drawn FPS over 30 minutes, with reported capture drops at most 0.1% and no persistent frame queue. 10 points: controlled high-speed-camera controller-to-screen tests establish median and p95 delay, show no material regression versus the known working player, and compare with OBS and a direct HDMI display where available. 8 points: native-resolution rendering and reversible presentation options preserve timing; compare median/p95 GPU time and app frame age under equivalent load. |
| Stability and recovery | 20 | 8 points: eight-hour mixed play/idle run without crash or unbounded memory/log growth. 8 points: ten physical unplug/replug cycles, repeated pause/resume, mode changes, unavailable-device and permission-denied cases recover with useful messages and no abandoned sessions. 4 points: quit/relaunch and quit-during-connect are safe and preferences remain valid. |
| Audio | 10 | 4 points: card audio is selected and heard correctly, without Mac microphone substitution. 4 points: two-hour listening check has no dropouts or progressive audio/video drift; timing comparison records the observed offset. 2 points: volume, mute, output-device changes and reconnect preserve expected behavior. |
| Picture | 10 | 4 points: correct aspect ratio, letterboxing and scaling at windowed/fullscreen sizes. 4 points: SDR calibration confirms black/white levels and color conversion against reference patterns; no clipped shadows or washed-out blacks. 2 points: moving scenes show no unacceptable tearing, flicker or artifacts in the user's selected preview mode. |
| Usability and controls | 10 | 4 points: card and mode choices are clear, unsupported modes disabled, pause/reconnect and audio controls understandable. 4 points: fullscreen, hidden controls and selected preferences restore correctly; keyboard escape routes remain available. 2 points: useful status and diagnostics distinguish current measurements, stalled feed, audio failure and unsupported features. |
| Hardware and mode handling | 8 | 4 points: live 720p60, 1080p60 and 1440p30 checks on this card agree with capabilities; highest-FPS and fixed/fractional timing selection tests pass. 4 points: real 4K60/59.94 is conditional on compatible capture hardware, 4K30 is not silently substituted, and the current 60 Hz display limit is explicit. Sustained real 4K60 remains uncertified until tested. |
| Accessibility | 6 | 3 points: all controls have meaningful VoiceOver names/state and can be used without a mouse. 3 points: focus order, dialog dismissal, text contrast and status/error accessibility are checked with VoiceOver and keyboard in both layouts. |
| Privacy and public release | 6 | 2 points: local-only operation, bounded diagnostics and no captured content/credentials transmitted. 2 points: clean public repository, documented ownership/license decision, no secrets or personal runtime logs, reproducible build and tests. 2 points: Applications installation, icon, metadata and verified signature work; local ad-hoc signing and absence of notarization are disclosed. |

**Total: 100 points.** Subchecks can be scored separately; a category is not passed merely because its feature exists.

## Performance preservation gates

Use the same Mac, power mode, card/USB port, capture mode, preview mode, screen geometry, controls and representative scene. Allow warmup; record at least three alternating baseline/candidate runs. Report received/drawn FPS, drops, sample distributions and measurement limitations. A changing game or a short sequential sample is supporting evidence, not final non-regression certification.

For app processing, flag a candidate for further investigation if median GPU execution increases by more than max(10% of the baseline, 0.10 ms), or median app frame age increases by more than max(10%, 0.25 ms). Also examine p95 and repeated outliers; do not accept a change from its average alone. For measured controller-to-screen timing, investigate a median or p95 increase exceeding max(5 ms, the validated measurement uncertainty). These are proposed engineering acceptance margins, not claims about what humans can perceive.

Any reproducible audio loss, broken mode selection, crash, growing frame queue, or significant sustained FPS/drop regression blocks retaining an update until fixed or reverted. Experiments remain optional and reversible. A prettier image cannot compensate for a failed performance gate.

## Delay and hardware honesty

Zero end-to-end latency is not a defensible acceptance threshold for this capture pipeline. Report actual measured delay and pursue the lowest practical value. The app cannot remove delay incurred before receiving a frame. “0.24 ms app frame age” excludes card buffering, GPU execution, compositor and display scanout, and does not establish 0.24 ms controller response.

Current card: 1080p60 and 1440p30 USB capture; no advertised 4K capture or 1080p120 on this Mac. Current display: 60 Hz. Native 4K60 certification requires compatible hardware. HDR is not supported by this 8-bit SDR player and must not be implied by its scaling features.

## Evidence currently available

The earlier installed player had approximately 60 received/drawn FPS, no reported capture drops during short gameplay samples, 0.51 ms mean GPU execution and 0.24 ms mean app frame age. The user confirmed working sound and good picture but similar controller delay. Mode policy and synthetic NV12 rendering tests passed. This does not satisfy the longer soak, physical recovery, calibrated color, VoiceOver or end-to-end latency checks above. No numeric current score is assigned without a check-by-check audit.
