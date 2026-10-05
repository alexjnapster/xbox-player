# Apple and capture-chip performance options

Checked 5 October 2026.

## UGREEN input versus capture output

The official UGREEN India listing for 15389 advertises 4K HDMI input, with 2K30 / 1080p60 capture output and no driver installation. That matches this Mac's enumerated modes: 2560×1440 at approximately 30 fps, 1920×1080 at approximately 60 fps, and no 3840×2160 format.

Source: [UGREEN 15389 specifications](https://www.ugreenindia.com/products/ugreen-hdmi-video-capture-card-4k-input-2k-30hz-1080p-60fps-usb-a-usb-c-15389).

## Apple features

The app already uses Metal textures backed by captured pixel buffers and avoids CPU image-copy/scaling work. Apple offers a Metal Performance HUD for FPS, GPU time and frame interval, plus Metal display-link APIs designed for frame pacing and low latency. These are tools/APIs, not a way to unlock unsupported capture-card modes.

Sources: [Metal HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics), [Metal display-link guidance](https://developer.apple.com/documentation/metal/achieving-smooth-frame-rates-with-a-metal-display-link).

The app's optional Fast Preview experiment uses the documented Metal-layer display synchronization control and schedules rendering on capture-frame arrival. Disabling synchronization changes frame presentation behavior and can affect tearing/pacing. Its value is evaluated using measured app frame age and delivered/drawn FPS; total input latency remains unmeasured.

Source: [CAMetalLayer displaySyncEnabled](https://developer.apple.com/documentation/quartzcore/cametallayer/displaysyncenabled).

## Chip firmware and drivers

USB enumeration identifies MacroSilicon as vendor, but does not reliably establish this board's exact chip model. No official UGREEN Mac driver or model-specific firmware performance upgrade was verified in this research. The product is advertised as UVC plug-and-play.

Community projects do exist. `ms213x_flash` is a flashing tool for specified MS213x chips, not proof of an FPS upgrade for UGREEN 15389. The `macrosilicon_firmware` project lists different supported chips and features such as GPIO, editable EDID and signal access; it does not establish support for this exact card or unlocking 4K60.

Sources: [ms213x_flash project](https://github.com/steve-m/ms213x_flash), [macrosilicon_firmware project](https://github.com/kraln/macrosilicon_firmware).

No proprietary driver, firmware image, EDID rewrite, clock adjustment, or device-register write was installed/applied. Experimental app rendering is reversible through the View menu. Capture-card firmware modification was not justified by compatibility or performance evidence.

## Scaling options follow-up

The installed player caps the drawing surface at captured detail and delegates enlargement to macOS. Apple MetalFX spatial upscaling accepts a color image and could be evaluated for quality, but no lower-latency result versus this path has been established. Temporal upscaling requires jittered color, motion and depth inputs from a rendering engine, which this HDMI capture feed does not supply. No extra scaler was added solely on a speculative speed claim.

Source: [Apple MetalFX spatial and temporal requirements](https://developer.apple.com/videos/play/wwdc2022/10103/).
