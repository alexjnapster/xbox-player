# Recommended Xbox settings for this capture setup

5 October 2026. These are setup-specific recommendations for the UGREEN 15389/CM629, the current 8-bit SDR Xbox Player and the 60 Hz Studio Display. They have not been applied or confirmed on the console.

Open Settings → General → TV & display options.

| Location / setting | Recommended value | Reason |
| --- | --- | --- |
| Resolution | 1080p | Matches the fastest full-HD capture mode; avoids unnecessary card downscaling |
| Refresh rate, if offered | 60 Hz | Matches captured cadence and screen refresh |
| Video fidelity & overscan → Overrides | Auto-detect | Start with negotiated HDMI capabilities |
| Video fidelity & overscan → Color depth | 24 bits per pixel (8-bit) | Matches this SDR player |
| Video fidelity & overscan → Color space | Standard (recommended) | Use as the baseline for the limited-range video path; verify black levels with calibration |
| Video modes → Allow 4K | Off | Keep games from switching output away from the chosen 1080p signal |
| Video modes → Allow HDR10 / Auto HDR / Dolby Vision / Dolby Vision for Gaming | Off, where present | The player does not implement HDR tone mapping |
| Video modes → Variable refresh rate | Off | Establish a fixed 60 Hz capture baseline; no VRR-to-Mac-display path is implemented |
| Video modes → Allow YCC 4:2:2 | Off | No need to enable this HDMI compatibility option for the baseline 1080p SDR setup |

Menus and available switches vary by Xbox model and connected device. Auto Low Latency Mode signals a compatible display to use its low-latency mode; it does not switch the Mac capture application into one. It is not a remedy for capture buffering.

Open Settings → General → Volume & audio output → Speaker audio → HDMI audio and choose **Stereo uncompressed**. The card exposes stereo PCM, and the player monitors that audio to the Mac's selected output.

Inside games, choose **Performance / 60 FPS** instead of a 30 FPS quality mode when offered. Output resolution and game rendering rate are different: setting Xbox output to 1080p does not force every game to run at 60 FPS. Disable motion blur if clearer movement helps; that is a visual preference, not a demonstrated capture-latency optimization. Avoid attempting 120 Hz with this capture baseline.

In Xbox Player use **1080p · Max 60 FPS**, **Fast Preview enabled**, and fullscreen. This preserves the tested configuration. HDR/VRR and color choices are compatibility recommendations, not measured input-lag improvements. A perceptible latency improvement still requires actual controller-to-screen testing.

Sources: [Xbox display setup and video modes](https://news.xbox.com/en-us/2020/11/06/is-your-tv-ready-to-power-your-dreams/), [Xbox display settings support](https://support.xbox.com/en-US/help/hardware-network/display-sound/change-tv-display-resolution), [Xbox audio output support](https://support.xbox.com/en-US/help/hardware-network/display-sound/choosing-speaker-audio-output). Xbox Support pages require JavaScript; the published Xbox Wire guide verifies display-menu locations and HDR/VRR controls. Exact labels can change between console software versions. Recommended values also reflect the capture modes and SDR/stereo paths verified locally.
