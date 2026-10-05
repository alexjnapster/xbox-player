import Cocoa
import AVFoundation
import MetalKit

struct FrameMetrics {
    let captureFPS: Double
    let renderFPS: Double
    let gpuMilliseconds: Double
    let applicationFrameAgeMilliseconds: Double
    let maximumCaptureGapMilliseconds: Double
    let droppedFrames: Int
}

// Capture callbacks only replace one retained frame; rendering never queues old frames.
final class VideoView: MTKView, MTKViewDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let frameLock = NSLock()
    private var latestFrame: CVPixelBuffer?
    private var textureCache: CVMetalTextureCache!
    private var commandQueue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!
    private var inputSize = CGSize(width: 1920, height: 1080)
    private var captureCount = 0
    private var captureStart = CACurrentMediaTime()
    private var drawsOnArrival = false
    private var renderPending = false
    private var latestArrival = CACurrentMediaTime()
    private var renderedFrames = 0
    private var gpuTotal = 0.0
    private var gpuSamples = 0
    private var frameAgeTotal = 0.0
    private var frameAgeSamples = 0
    private var droppedFrames = 0
    private var lastCaptureArrival: Double?
    private var maximumCaptureGap = 0.0
    var onRate: ((FrameMetrics, Int, Int) -> Void)?

    init(metalPreview: Bool) throws {
        guard let gpu = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "XboxPlayer", code: 5, userInfo: [NSLocalizedDescriptionKey: "Metal graphics unavailable"])
        }
        super.init(frame: .zero, device: gpu)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        autoResizeDrawable = false
        (layer as? CAMetalLayer)?.magnificationFilter = .linear
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        preferredFramesPerSecond = 60
        (layer as? CAMetalLayer)?.maximumDrawableCount = 2
        guard let commands = gpu.makeCommandQueue() else {
            throw NSError(domain: "XboxPlayer", code: 7, userInfo: [NSLocalizedDescriptionKey: "Metal command queue unavailable"])
        }
        commandQueue = commands
        guard CVMetalTextureCacheCreate(nil, nil, gpu, nil, &textureCache) == kCVReturnSuccess, textureCache != nil else {
            throw NSError(domain: "XboxPlayer", code: 8, userInfo: [NSLocalizedDescriptionKey: "Video texture cache unavailable"])
        }
        let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 position [[position]]; float2 uv; };
        vertex V videoVertex(uint i [[vertex_id]]) {
            float2 p[3] = {float2(-1,-1), float2(-1,3), float2(3,-1)};
            float2 uv[3] = {float2(0,1), float2(0,-1), float2(2,1)};
            return {float4(p[i],0,1),uv[i]};
        }
        fragment float4 videoFragment(V v [[stage_in]], texture2d<float> yTex [[texture(0)]], texture2d<float> uvTex [[texture(1)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            float y = (yTex.sample(s,v.uv).r - 16.0/255.0) * (255.0/219.0);
            float2 c = (uvTex.sample(s,v.uv).rg - 128.0/255.0) * (255.0/224.0);
            float3 rgb = float3(y+1.5748*c.y, y-0.187324*c.x-0.468124*c.y, y+1.8556*c.x);
            return float4(clamp(rgb,0.0,1.0),1);
        }
        """
        let library = try gpu.makeLibrary(source: shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "videoVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "videoFragment")
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        pipeline = try gpu.makeRenderPipelineState(descriptor: descriptor)
        delegate = self
    }
    required init(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); updateDrawableSize() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateDrawableSize() }
    func setInputSize(width: Int, height: Int) {
        let size = CGSize(width: width, height: height)
        if inputSize != size { inputSize = size; updateDrawableSize() }
    }
    private func updateDrawableSize() {
        let pixels = convertToBacking(bounds).size
        guard pixels.width > 0, pixels.height > 0 else { return }
        // Keep the surface aspect ratio while avoiding output pixels above the captured feed.
        let scale = min(1, inputSize.width / pixels.width, inputSize.height / pixels.height)
        let target = CGSize(width: max(1, (pixels.width * scale).rounded()), height: max(1, (pixels.height * scale).rounded()))
        if drawableSize != target { drawableSize = target }
    }
    func setFrameDriven(_ enabled: Bool) {
        frameLock.lock(); drawsOnArrival = enabled; frameLock.unlock()
        isPaused = enabled
        (layer as? CAMetalLayer)?.displaySyncEnabled = !enabled
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func resetStatistics() {
        captureCount = 0; captureStart = CACurrentMediaTime(); lastCaptureArrival = nil; maximumCaptureGap = 0
        frameLock.lock()
        renderedFrames = 0; gpuTotal = 0; gpuSamples = 0; frameAgeTotal = 0; frameAgeSamples = 0; droppedFrames = 0
        frameLock.unlock()
    }
    func resetFrame() {
        frameLock.lock(); latestFrame = nil; frameLock.unlock()
        // Fast Preview pauses automatic drawing, so explicitly clear a disconnected feed.
        DispatchQueue.main.async { [weak self] in self?.draw() }
    }
    func secondsSinceLatestFrame() -> Double? {
        frameLock.lock(); defer { frameLock.unlock() }
        guard latestFrame != nil else { return nil }
        return max(0, CACurrentMediaTime() - latestArrival)
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()
        frameLock.lock(); latestFrame = frame; latestArrival = now
        let requestRender = drawsOnArrival && !renderPending
        if requestRender { renderPending = true }
        frameLock.unlock()
        if requestRender {
            DispatchQueue.main.async {
                self.draw()
                self.frameLock.lock(); self.renderPending = false; self.frameLock.unlock()
            }
        }
        if let previous = lastCaptureArrival { maximumCaptureGap = max(maximumCaptureGap, now - previous) }
        lastCaptureArrival = now
        captureCount += 1
        let elapsed = CACurrentMediaTime() - captureStart
        if elapsed >= 2 {
            frameLock.lock()
            let metrics = FrameMetrics(captureFPS: Double(captureCount) / elapsed,
                                       renderFPS: Double(renderedFrames) / elapsed,
                                       gpuMilliseconds: gpuSamples == 0 ? 0 : gpuTotal / Double(gpuSamples) * 1000,
                                       applicationFrameAgeMilliseconds: frameAgeSamples == 0 ? 0 : frameAgeTotal / Double(frameAgeSamples) * 1000,
                                       maximumCaptureGapMilliseconds: maximumCaptureGap * 1000, droppedFrames: droppedFrames)
            renderedFrames = 0; gpuTotal = 0; gpuSamples = 0; frameAgeTotal = 0; frameAgeSamples = 0
            frameLock.unlock()
            captureCount = 0; captureStart = CACurrentMediaTime(); maximumCaptureGap = 0
            let width = CVPixelBufferGetWidth(frame), height = CVPixelBufferGetHeight(frame)
            DispatchQueue.main.async { self.onRate?(metrics, width, height) }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameLock.lock(); droppedFrames += 1; frameLock.unlock()
    }
    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = commandQueue.makeCommandBuffer() else { return }
        // Acquire a drawable before selecting the frame, so drawable waits cannot age our selection.
        frameLock.lock(); let frame = latestFrame; let arrival = latestArrival; frameLock.unlock()
        guard let frame = frame, CVPixelBufferGetPlaneCount(frame) == 2 else {
            command.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            command.present(drawable); command.commit(); return
        }
        guard encode(frame: frame, pass: pass, command: command, targetSize: drawableSize) else { return }
        frameLock.lock(); renderedFrames += 1; frameAgeTotal += max(0, CACurrentMediaTime()-arrival); frameAgeSamples += 1; frameLock.unlock()
        command.addCompletedHandler { [weak self] command in
            guard let self = self, command.gpuEndTime >= command.gpuStartTime, command.gpuStartTime > 0 else { return }
            self.frameLock.lock(); self.gpuTotal += command.gpuEndTime-command.gpuStartTime; self.gpuSamples += 1; self.frameLock.unlock()
        }
        command.present(drawable)
        command.commit()
    }
    @discardableResult
    func encode(frame: CVPixelBuffer, pass: MTLRenderPassDescriptor, command: MTLCommandBuffer, targetSize: CGSize) -> Bool {
        var yRef: CVMetalTexture?, uvRef: CVMetalTexture?
        let width = CVPixelBufferGetWidth(frame), height = CVPixelBufferGetHeight(frame)
        guard CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, frame, nil, .r8Unorm, width, height, 0, &yRef) == kCVReturnSuccess,
              CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, frame, nil, .rg8Unorm, width/2, height/2, 1, &uvRef) == kCVReturnSuccess,
              let yRef = yRef, let uvRef = uvRef,
              let y = CVMetalTextureGetTexture(yRef), let uv = CVMetalTextureGetTexture(uvRef),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
        let scale = min(targetSize.width / Double(width), targetSize.height / Double(height))
        let w = Double(width)*scale, h = Double(height)*scale
        encoder.setViewport(MTLViewport(originX: (targetSize.width-w)/2, originY: (targetSize.height-h)/2, width: w, height: h, znear: 0, zfar: 1))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(y, index: 0); encoder.setFragmentTexture(uv, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        // Keep IOSurface-backed textures alive until the GPU finishes using them.
        command.addCompletedHandler { _ in _ = (frame, yRef, uvRef) }
        return true
    }
    func verifyRendering() throws {
        for (width, height) in [(1280,720), (1920,1080), (2560,1440), (3840,2160)] {
            for brightness: UInt8 in [16,235] {
                var buffer: CVPixelBuffer?
                let attributes: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
                guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes as CFDictionary, &buffer) == kCVReturnSuccess, let frame = buffer else {
                    throw NSError(domain: "XboxPlayerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate synthetic NV12 frame"])
                }
                CVPixelBufferLockBaseAddress(frame, [])
                memset(CVPixelBufferGetBaseAddressOfPlane(frame,0), Int32(brightness), CVPixelBufferGetBytesPerRowOfPlane(frame,0)*height)
                memset(CVPixelBufferGetBaseAddressOfPlane(frame,1), 128, CVPixelBufferGetBytesPerRowOfPlane(frame,1)*height/2)
                CVPixelBufferUnlockBaseAddress(frame, [])
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
                descriptor.usage = [.renderTarget]; descriptor.storageMode = .shared
                guard let target = device!.makeTexture(descriptor: descriptor), let command = commandQueue.makeCommandBuffer() else { throw NSError(domain: "XboxPlayerTests", code: 2) }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target; pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
                guard encode(frame: frame, pass: pass, command: command, targetSize: CGSize(width: width,height: height)) else { throw NSError(domain: "XboxPlayerTests", code: 3) }
                command.commit(); command.waitUntilCompleted()
                if let error = command.error { throw error }
                var pixel: [UInt8] = [0,0,0,0]
                target.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(width/2,height/2,1,1), mipmapLevel: 0)
                guard pixel[3] == 255, pixel.prefix(3).allSatisfy({ brightness == 16 ? $0 <= 2 : $0 >= 253 }) else {
                    throw NSError(domain: "XboxPlayerTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "NV12 black/white conversion mismatch: \(pixel)"])
                }
            }
            print("Metal NV12 rendering passed: \(width)×\(height), black and white reference pixels")
        }
    }

}

final class Player: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    let videoSession = AVCaptureSession()
    let audioSession = AVCaptureSession()
    let audioOutput = AVCaptureAudioPreviewOutput()
    let queue = DispatchQueue(label: "XboxPlayer.capture", qos: .userInteractive)
    let video: VideoView
    let videoOutput = AVCaptureVideoDataOutput()
    let frameQueue = DispatchQueue(label: "XboxPlayer.frames", qos: .userInteractive)
    var connectionStatus = ""
    var audioAvailable = false
    var audioStatus = "Waiting for audio"
    var stalled = false
    var connectionStartedAt = CACurrentMediaTime()
    var healthTimer: Timer?
    let feedMessage = NSTextField(labelWithString: "Connecting to capture card…")
    let controlsMenuItem = NSMenuItem(title: "Show / Hide Controls", action: #selector(toggleControls), keyEquivalent: "h")
    var lastMetrics: [String: Any] = [:]
    let status = NSTextField(labelWithString: "Connecting to UGREEN…")
    var window: NSWindow!
    var muteButton: NSButton!
    var volume: NSSlider!
    var connecting = false
    var capturePaused = false
    var receiving = false
    let preferences = UserDefaults.standard
    let diagnosticsQueue = DispatchQueue(label: "XboxPlayer.diagnostics", qos: .utility)
    var reconnectWork: DispatchWorkItem?
    var barHeight: NSLayoutConstraint!
    var controlBar: NSStackView!
    var resolution: NSPopUpButton!
    var devicePicker: NSPopUpButton!
    var availableDevices: [AVCaptureDevice] = []
    var captureFPS = 60.0
    var fastPreview = false
    let fastPreviewMenuItem = NSMenuItem(title: "Experimental Fast Preview", action: #selector(toggleFastPreview), keyEquivalent: "e")
    var activeDeviceID = ""
    var muted = false
    var observations: [NSObjectProtocol] = []

    init(nativePlayer: Bool) throws {
        video = try VideoView(metalPreview: true)
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 690),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Xbox Player"
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 960, height: 560)
        window.setFrameAutosaveName("XboxPlayerWindow")
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        let content = window.contentView!
        video.translatesAutoresizingMaskIntoConstraints = false
        let bar = NSStackView()
        controlBar = bar
        bar.orientation = .horizontal
        bar.spacing = 12
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        bar.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 12)
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        resolution = NSPopUpButton(frame: .zero, pullsDown: false)
        resolution.addItems(withTitles: PlayMode.allCases.map { $0.title })
        resolution.autoenablesItems = false
        devicePicker = NSPopUpButton(frame: .zero, pullsDown: false)
        devicePicker.target = self; devicePicker.action = #selector(changeDevice)
        devicePicker.setAccessibilityLabel("Capture card")
        let savedMode = PlayMode(rawValue: preferences.integer(forKey: "playMode")) ?? .fastest1080
        resolution.selectItem(at: savedMode.rawValue)
        refreshDevices()
        resolution.setAccessibilityLabel("Video mode")
        resolution.target = self; resolution.action = #selector(changeResolution)
        resolution.toolTip = "Modes depend on your card. 4K60 requires a card that exposes 3840×2160 at 60 fps to macOS."
        let reconnect = NSButton(title: "Reconnect", target: self, action: #selector(connect))
        muteButton = NSButton(title: "Mute", target: self, action: #selector(toggleMute))
        let savedVolume = preferences.object(forKey: "volume") == nil ? 0.8 : preferences.double(forKey: "volume")
        muted = preferences.bool(forKey: "muted")
        muteButton.title = muted ? "Unmute" : "Mute"
        volume = NSSlider(value: min(1, max(0, savedVolume)), minValue: 0, maxValue: 1, target: self, action: #selector(changeVolume))
        volume.toolTip = "Xbox volume"
        volume.setAccessibilityLabel("Xbox volume")
        volume.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let full = NSButton(title: "Fullscreen", target: self, action: #selector(fullscreen))
        bar.orientation = .vertical; bar.alignment = .leading; bar.spacing = 6
        let controls = NSStackView(views: [devicePicker, resolution, reconnect, muteButton, volume, full])
        controls.orientation = .horizontal; controls.spacing = 12
        bar.addArrangedSubview(controls); bar.addArrangedSubview(status)
        content.addSubview(video)
        content.addSubview(bar)
        feedMessage.translatesAutoresizingMaskIntoConstraints = false
        feedMessage.font = .systemFont(ofSize: 18, weight: .medium)
        feedMessage.textColor = .white
        feedMessage.alignment = .center
        feedMessage.setAccessibilityLabel("Capture status")
        content.addSubview(feedMessage)
        NSLayoutConstraint.activate([
            feedMessage.centerXAnchor.constraint(equalTo: video.centerXAnchor),
            feedMessage.centerYAnchor.constraint(equalTo: video.centerYAnchor),
            feedMessage.widthAnchor.constraint(lessThanOrEqualTo: video.widthAnchor, constant: -48),
            video.topAnchor.constraint(equalTo: content.topAnchor), video.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            video.trailingAnchor.constraint(equalTo: content.trailingAnchor), video.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor), bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        barHeight = bar.heightAnchor.constraint(equalToConstant: 76)
        barHeight.isActive = true
        controlBar.isHidden = preferences.bool(forKey: "controlsHidden")
        barHeight.constant = controlBar.isHidden ? 0 : 76
        controlsMenuItem.state = controlBar.isHidden ? .off : .on
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    kCVPixelBufferMetalCompatibilityKey as String: true]
        videoOutput.setSampleBufferDelegate(video, queue: frameQueue)
        fastPreview = preferences.bool(forKey: "fastPreview")
        video.setFrameDriven(fastPreview)
        fastPreviewMenuItem.state = fastPreview ? .on : .off
        video.onRate = { [weak self] metrics, width, height in
            let rate = metrics.captureFPS
            guard let self = self, !self.connecting, self.receiving else { return }
            self.stalled = false
            self.feedMessage.isHidden = true
            self.video.setInputSize(width: width, height: height)
            let audioLabel = self.muted ? "Muted" : self.audioAvailable ? "Audio on" : self.audioStatus
            self.status.stringValue = "\(height)p · \(String(format: "%.1f", rate)) FPS · GPU \(String(format: "%.2f", metrics.gpuMilliseconds)) ms · \(audioLabel)"
            let report: [String: Any] = ["receivedWidth": width, "receivedHeight": height, "receivedFPS": rate,
                                       "requestedCaptureFPS": self.captureFPS, "displayMaximumFPS": self.window.screen?.maximumFramesPerSecond ?? 60,
                                       "rendererTargetFPS": self.video.preferredFramesPerSecond,
                                       "drawableWidth": Int(self.video.drawableSize.width), "drawableHeight": Int(self.video.drawableSize.height),
                                       "fullscreen": self.window.styleMask.contains(.fullScreen), "controlsHidden": self.controlBar.isHidden,
                                       "renderFPS": metrics.renderFPS, "gpuMilliseconds": metrics.gpuMilliseconds,
                                       "applicationFrameAgeMilliseconds": metrics.applicationFrameAgeMilliseconds,
                                       "maximumCaptureGapMilliseconds": metrics.maximumCaptureGapMilliseconds,
                                       "droppedFrames": metrics.droppedFrames, "audioAvailable": self.audioAvailable,
                                       "audioStatus": self.audioStatus, "muted": self.muted, "volume": self.volume.doubleValue,
                                       "captureState": "receiving", "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                                       "timestamp": ISO8601DateFormatter().string(from: Date()),
                                       "previewMode": self.fastPreview ? "frame arrival / unsynchronized" : "display synchronized",
                                       "renderer": "Metal newest frame", "endToEndLatencyMeasured": false]
            self.lastMetrics = report
            self.saveDiagnostics(report)

        }
        for session in [videoSession, audioSession] {
            observations.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
                guard let self = self else { return }
                if session === self.videoSession {
                    self.receiving = false; self.lastMetrics = [:]
                    self.showFeedMessage("Video stopped — press Command–R to reconnect")
                    self.queue.async { self.videoSession.stopRunning(); self.audioSession.stopRunning(); self.video.resetFrame() }
                } else { self.audioAvailable = false; self.audioStatus = "Audio error: \(error?.localizedDescription ?? "Reconnect the card")" }
                self.status.stringValue = "Capture error: \(error?.localizedDescription ?? "Reconnect the card")"
            })
        }
        observations.append(NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] note in
            if let device = note.object as? AVCaptureDevice, device.uniqueID == self?.activeDeviceID {
                guard let self = self else { return }
                self.receiving = false; self.lastMetrics = [:]; self.audioAvailable = false
                self.showFeedMessage("Capture card disconnected")
                self.status.stringValue = "Capture card disconnected — waiting for it to reconnect"
                self.saveDiagnostics(["captureState": "disconnected", "timestamp": ISO8601DateFormatter().string(from: Date())])
                self.queue.async { self.videoSession.stopRunning(); self.audioSession.stopRunning(); self.video.resetFrame() }
            }
        })
        observations.append(NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self, !self.capturePaused, let device = note.object as? AVCaptureDevice else { return }
            let savedDevice = self.preferences.string(forKey: "deviceID")
            let matchesSelection = device.uniqueID == self.activeDeviceID || device.uniqueID == savedDevice ||
                (self.activeDeviceID.isEmpty && savedDevice == nil && device.localizedName.uppercased().contains("UGREEN"))
            guard matchesSelection else { return }
            self.reconnectWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.connect() }
            self.reconnectWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        })
        if !window.setFrameUsingName("XboxPlayerWindow") { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkFeedHealth() }
        connect()
        if preferences.bool(forKey: "fullscreen") { window.toggleFullScreen(nil) }
    }

    func showFeedMessage(_ message: String) {
        feedMessage.stringValue = message; feedMessage.isHidden = false
        feedMessage.setAccessibilityValue(message)
    }
    func checkFeedHealth() {
        if connecting {
            if CACurrentMediaTime() - connectionStartedAt > 15 {
                showFeedMessage("Still connecting — check Camera and Microphone access in System Settings")
            }
            return
        }
        guard receiving else { return }
        let age = video.secondsSinceLatestFrame() ?? max(0, CACurrentMediaTime() - connectionStartedAt)
        guard age > 3, !stalled else { return }
        stalled = true; lastMetrics = [:]
        showFeedMessage("Video paused — press Command–R to reconnect")
        status.stringValue = "No new video frames for over 3 seconds · \(audioStatus)"
        saveDiagnostics(["captureState": "stalled", "secondsSinceLatestFrame": age,
                         "timestamp": ISO8601DateFormatter().string(from: Date())])
    }

    func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "About Xbox Player", action: #selector(about), keyEquivalent: "")
        about.target = self; appMenu.addItem(about); appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Xbox Player", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        let full = NSMenuItem(title: "Toggle Fullscreen", action: #selector(fullscreen), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]; full.target = self; viewMenu.addItem(full)
        let entries: [(String, Selector, String)] = [
            ("Mute / Unmute", #selector(toggleMute), "m"),
            ("Reconnect Capture Card", #selector(connect), "r"),
            ("Pause Capture", #selector(pauseCapture), "d"),
            ("Capture Card Capabilities", #selector(showCapabilities), "i"),
            ("Performance Statistics", #selector(showPerformance), "p")
        ]
        for (title, action, key) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; viewMenu.addItem(item)
        }
        controlsMenuItem.keyEquivalentModifierMask = [.command, .shift]; controlsMenuItem.target = self; viewMenu.addItem(controlsMenuItem)
        viewMenu.addItem(.separator())
        fastPreviewMenuItem.target = self; viewMenu.addItem(fastPreviewMenuItem)
        viewItem.submenu = viewMenu; menu.addItem(viewItem)
        NSApp.mainMenu = menu
    }

    @MainActor func permission(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }

    @objc func connect() {
        guard !connecting else { return }
        capturePaused = false
        connecting = true; receiving = false; stalled = false; lastMetrics = [:]
        reconnectWork?.cancel(); audioAvailable = false
        showFeedMessage("Connecting to capture card…")
        refreshDevices()
        let mode = PlayMode(rawValue: resolution.indexOfSelectedItem) ?? .fastest1080
        let deviceID = availableDevices.indices.contains(devicePicker.indexOfSelectedItem) ? availableDevices[devicePicker.indexOfSelectedItem].uniqueID : ""
        resolution.isEnabled = false; devicePicker.isEnabled = false
        status.stringValue = "Connecting to capture card…"
        connectionStartedAt = CACurrentMediaTime()
        saveDiagnostics(["captureState": "connecting", "phase": "permissions",
                         "videoPermission": AVCaptureDevice.authorizationStatus(for: .video).rawValue,
                         "audioPermission": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
                         "timestamp": ISO8601DateFormatter().string(from: Date())])
        Task { @MainActor in
            self.status.stringValue = "Checking Camera permission…"
            self.saveDiagnostics(["captureState": "connecting", "phase": "camera permission", "timestamp": ISO8601DateFormatter().string(from: Date())])
            let camera = await permission(.video)
            guard camera else {
                await MainActor.run {
                    self.status.stringValue = "Allow Xbox Player in System Settings → Privacy & Security → Camera"
                    self.showFeedMessage("Camera permission needed — see System Settings")
                    self.connecting = false; self.resolution.isEnabled = true; self.devicePicker.isEnabled = true
                }
                return
            }
            self.status.stringValue = "Checking Microphone permission…"
            self.saveDiagnostics(["captureState": "connecting", "phase": "microphone permission", "timestamp": ISO8601DateFormatter().string(from: Date())])
            let microphone = await permission(.audio)
            self.status.stringValue = "Opening capture card…"
            self.saveDiagnostics(["captureState": "connecting", "phase": "device configuration", "timestamp": ISO8601DateFormatter().string(from: Date())])
            let previewVolume = await MainActor.run { self.muted ? Float(0) : Float(self.volume.doubleValue) }
            queue.async { self.configure(audioAllowed: microphone, previewVolume: previewVolume, mode: mode, deviceID: deviceID) }
        }
    }

    func configure(audioAllowed: Bool, previewVolume: Float, mode: PlayMode, deviceID: String) {
        videoSession.stopRunning(); audioSession.stopRunning(); video.resetFrame()
        for session in [videoSession, audioSession] {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
        }
        do {
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
            guard let device = devices.first(where: { $0.uniqueID == deviceID }) else {
                throw NSError(domain: "XboxPlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Capture card not found — connect it and click Reconnect"])
            }
            guard let choice = chooseMode(mode, candidates: describeModes(device)) else {
                throw NSError(domain: "XboxPlayer", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(mode.title) is not supported by \(device.localizedName). Choose an available mode."])
            }
            let format = device.formats[choice.candidate.formatIndex]
            let range = format.videoSupportedFrameRateRanges[choice.candidate.rangeIndex]
            // Exact native durations avoid rounding an advertised fixed rate out of its range.
            let duration = abs(choice.fps - range.maxFrameRate) < 0.000001 ? range.minFrameDuration :
                           abs(choice.fps - range.minFrameRate) < 0.000001 ? range.maxFrameDuration :
                           CMTime(seconds: 1.0 / choice.fps, preferredTimescale: 1_000_000_000)
            // Construct the potentially throwing input before opening the session transaction.
            let input = try AVCaptureDeviceInput(device: device)
            videoSession.beginConfiguration()
            guard videoSession.canAddInput(input) else { videoSession.commitConfiguration(); throw NSError(domain: "XboxPlayer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot open UGREEN — close OBS and reconnect"]) }
            videoSession.addInput(input)
            guard videoSession.canAddOutput(videoOutput) else { videoSession.commitConfiguration(); throw NSError(domain: "XboxPlayer", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot start Metal video output"]) }
            videoSession.addOutput(videoOutput)
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                videoSession.commitConfiguration()
                device.unlockForConfiguration()
            } catch { videoSession.commitConfiguration(); throw error }
            var audioMessage = "audio permission needed"
            if audioAllowed {
                do {
                    let audioDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
                    // Match the selected card; never substitute the Mac microphone.
                    let linkedIDs = Set(device.linkedDevices.map { $0.uniqueID })
                    guard let audio = audioDevices.first(where: { linkedIDs.contains($0.uniqueID) }) ??
                                      audioDevices.first(where: { $0.localizedName == device.localizedName }) else {
                        throw NSError(domain: "XboxPlayer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Selected card audio not found"])
                    }
                    let audioInput = try AVCaptureDeviceInput(device: audio)
                    audioSession.beginConfiguration()
                    if audioSession.canAddInput(audioInput) && audioSession.canAddOutput(audioOutput) {
                        audioSession.addInput(audioInput); audioSession.addOutput(audioOutput)
                        audioOutput.volume = previewVolume
                        audioSession.commitConfiguration()
                        audioSession.startRunning()
                        audioMessage = audioSession.isRunning ? "Xbox audio on" : "Audio session did not start"
                    } else { audioSession.commitConfiguration(); audioMessage = "audio unavailable" }
                } catch { audioMessage = error.localizedDescription }
            }
            // Apply connection timing after all session configuration, including audio startup.
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoMinFrameDurationSupported { connection.videoMinFrameDuration = duration }
                if connection.isVideoMaxFrameDurationSupported { connection.videoMaxFrameDuration = duration }
            }
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
            frameQueue.sync { video.resetStatistics() }
            videoSession.startRunning()
            // macOS can reapply its preset at startup; commit the chosen native mode while running.
            videoSession.beginConfiguration()
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                videoSession.commitConfiguration()
                device.unlockForConfiguration()
            } catch { videoSession.commitConfiguration(); throw error }
            guard videoSession.isRunning, device.isConnected else {
                throw NSError(domain: "XboxPlayer", code: 9, userInfo: [NSLocalizedDescriptionKey: "Video session did not start — reconnect the card"])
            }
            let actualDimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let actualRate = 1.0 / CMTimeGetSeconds(device.activeVideoMinFrameDuration)
            let configuration: [String: Any] = ["width": actualDimensions.width, "height": actualDimensions.height,
                                               "deviceConfiguredFPS": actualRate, "renderer": "Metal newest frame"]
            saveDiagnostics(configuration)
            let message = "\(device.localizedName) · \(mode == .uhd60 ? "4K" : "\(mode.height)p") · \(String(format: "%.1f", choice.fps)) fps · \(audioMessage)"
            print(message)
            let finalAudioMessage = audioMessage
            DispatchQueue.main.async { self.video.setInputSize(width: Int(choice.candidate.width), height: Int(choice.candidate.height)); self.captureFPS = choice.fps; self.activeDeviceID = device.uniqueID; self.receiving = true; self.connectionStartedAt = CACurrentMediaTime(); self.audioAvailable = finalAudioMessage == "Xbox audio on"; self.audioStatus = finalAudioMessage; self.applyPreviewVolume(); self.preferences.set(device.uniqueID, forKey: "deviceID"); self.preferences.set(mode.rawValue, forKey: "playMode"); self.updateDisplayRate(); self.connectionStatus = message; self.status.stringValue = self.connectionStatus; self.connecting = false; self.resolution.isEnabled = true; self.devicePicker.isEnabled = true }
        } catch {
            videoSession.stopRunning(); audioSession.stopRunning(); video.resetFrame()
            print(error.localizedDescription)
            DispatchQueue.main.async {
                self.lastMetrics = [:]; self.receiving = false; self.audioAvailable = false
                self.showFeedMessage("Cannot start capture — see the status below")
                self.status.stringValue = error.localizedDescription; self.connecting = false
                self.resolution.isEnabled = true; self.devicePicker.isEnabled = true
                self.saveDiagnostics(["captureState": "error", "error": error.localizedDescription,
                                      "timestamp": ISO8601DateFormatter().string(from: Date())])
            }
        }
    }

    func describeModes(_ device: AVCaptureDevice) -> [ModeCandidate] {
        device.formats.enumerated().flatMap { index, format in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return format.videoSupportedFrameRateRanges.enumerated().map { rangeIndex, range in
                ModeCandidate(formatIndex: index, rangeIndex: rangeIndex, width: d.width, height: d.height,
                              minimumFPS: range.minFrameRate, maximumFPS: range.maxFrameRate,
                              isNV12: CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            }
        }
    }
    func refreshDevices() {
        let previous = availableDevices.indices.contains(devicePicker.indexOfSelectedItem) ? availableDevices[devicePicker.indexOfSelectedItem].uniqueID : preferences.string(forKey: "deviceID")
        availableDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
        devicePicker.removeAllItems()
        availableDevices.forEach { devicePicker.addItem(withTitle: $0.localizedName) }
        if let index = availableDevices.firstIndex(where: { $0.uniqueID == previous }) ?? availableDevices.firstIndex(where: { $0.localizedName.uppercased().contains("UGREEN") }) {
            devicePicker.selectItem(at: index)
        }
        updateModes()
    }
    func updateModes() {
        let device = availableDevices.indices.contains(devicePicker.indexOfSelectedItem) ? availableDevices[devicePicker.indexOfSelectedItem] : nil
        let candidates = device.map(describeModes) ?? []
        for mode in PlayMode.allCases {
            let choice = chooseMode(mode, candidates: candidates)
            let item = resolution.item(at: mode.rawValue)!
            item.isEnabled = choice != nil
            item.title = choice.map { mode == .uhd60 ? "4K · 60 FPS" : "\(mode.height)p · Max \(Int($0.fps.rounded())) FPS" } ?? "\(mode.title) — unavailable"
        }
        if resolution.selectedItem?.isEnabled != true, let available = PlayMode.allCases.first(where: { chooseMode($0, candidates: candidates) != nil }) {
            resolution.selectItem(at: available.rawValue)
        }
    }
    func updateDisplayRate() {
        // Capture may run faster than the screen; always show the newest frame at screen cadence.
        video.preferredFramesPerSecond = max(1, min(Int(captureFPS.rounded()), window.screen?.maximumFramesPerSecond ?? 60))
    }
    func windowDidChangeScreen(_ notification: Notification) { updateDisplayRate() }
    func windowDidEnterFullScreen(_ notification: Notification) { preferences.set(true, forKey: "fullscreen") }
    func windowDidExitFullScreen(_ notification: Notification) { preferences.set(false, forKey: "fullscreen") }
    @objc func pauseCapture() {
        guard !connecting else { return }
        capturePaused = true; receiving = false; lastMetrics = [:]; audioAvailable = false
        reconnectWork?.cancel()
        showFeedMessage("Capture paused — press Command–R to resume")
        status.stringValue = "Capture paused · card released for other apps"
        queue.async {
            self.videoSession.stopRunning(); self.audioSession.stopRunning(); self.video.resetFrame()
            for session in [self.videoSession, self.audioSession] {
                session.beginConfiguration()
                session.inputs.forEach { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }
                session.commitConfiguration()
            }
            self.saveDiagnostics(["captureState": "paused", "timestamp": ISO8601DateFormatter().string(from: Date())])
        }
    }
    @objc func changeDevice() { updateModes(); connect() }
    @objc func changeResolution() { connect() }
    @objc func fullscreen() { window.toggleFullScreen(nil) }
    @objc func toggleMute() { muted.toggle(); preferences.set(muted, forKey: "muted"); muteButton.title = muted ? "Unmute" : "Mute"; changeVolume() }
    func applyPreviewVolume() {
        let requestedVolume: Float = muted ? 0 : Float(volume.doubleValue)
        queue.async { self.audioOutput.volume = requestedVolume }
    }
    @objc func changeVolume() { preferences.set(volume.doubleValue, forKey: "volume"); applyPreviewVolume() }
    @objc func toggleFastPreview() {
        fastPreview.toggle(); preferences.set(fastPreview, forKey: "fastPreview")
        fastPreviewMenuItem.state = fastPreview ? .on : .off
        video.setFrameDriven(fastPreview)
        frameQueue.async { self.video.resetStatistics() }
    }
    @objc func toggleControls() {
        controlBar.isHidden.toggle()
        barHeight.constant = controlBar.isHidden ? 0 : 76
        preferences.set(controlBar.isHidden, forKey: "controlsHidden")
        controlsMenuItem.state = controlBar.isHidden ? .off : .on
    }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Xbox Player", .applicationVersion: "1.0",
            .credits: NSAttributedString(string: "Native console capture player.\nHighest supported 1080p FPS and hardware-aware 4K60.\nCapture FPS does not measure controller latency.")])
    }
    @objc func showCapabilities() {
        let alert = NSAlert()
        alert.messageText = "Capture card capabilities"
        if availableDevices.indices.contains(devicePicker.indexOfSelectedItem) {
            let device = availableDevices[devicePicker.indexOfSelectedItem]
            let candidates = describeModes(device)
            let lines = PlayMode.allCases.map { mode in
                chooseMode(mode, candidates: candidates).map { "\(mode.title): \(String(format: "%.2f", $0.fps)) fps available" } ?? "\(mode.title): unavailable on this card"
            }
            alert.informativeText = ([device.localizedName] + lines + ["Current display: up to \(window.screen?.maximumFramesPerSecond ?? 60) Hz.", "4K HDMI input support does not necessarily mean 4K USB capture."]).joined(separator: "\n")
        } else { alert.informativeText = "No capture card detected. Connect one and select Reconnect." }
        alert.addButton(withTitle: "OK"); alert.beginSheetModal(for: window)
    }
    @objc func showPerformance() {
        let alert = NSAlert()
        alert.messageText = "Performance statistics"
        if !receiving || stalled {
            alert.informativeText = status.stringValue + "\n\nNo current measurements. Press Command–R to reconnect."
        } else if let capture = lastMetrics["receivedFPS"] as? Double, let render = lastMetrics["renderFPS"] as? Double,
           let gpu = lastMetrics["gpuMilliseconds"] as? Double, let age = lastMetrics["applicationFrameAgeMilliseconds"] as? Double {
            alert.informativeText = String(format: "Capture: %.1f fps\nApp drawing: %.1f fps\nGPU rendering: %.2f ms/frame\nFrame age inside app: %.2f ms\n", capture, render, gpu, age) +
                "Late capture frames dropped: \(lastMetrics["droppedFrames"] ?? 0)\n\nThese measure the Mac capture/player pipeline. They do not measure the Xbox game's own FPS or controller-to-screen latency."
        } else { alert.informativeText = "Start capture and wait a few seconds for measurements." }
        alert.addButton(withTitle: "OK"); alert.beginSheetModal(for: window)
    }
    func saveDiagnostics(_ report: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
              let line = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        diagnosticsQueue.async {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Xbox Player", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try? data.write(to: base.appendingPathComponent("Last Session.json"), options: .atomic)
            let log = base.appendingPathComponent("Performance.jsonl")
            if FileManager.default.fileExists(atPath: log.path), let size = try? log.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 2_000_000 { try? Data().write(to: log) }
            if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: log) {
                defer { try? handle.close() }; do { try handle.seekToEnd(); try handle.write(contentsOf: line + Data([10])) } catch {}
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { healthTimer?.invalidate(); reconnectWork?.cancel(); queue.sync { videoSession.stopRunning(); audioSession.stopRunning() }; video.resetFrame() }
}

if CommandLine.arguments.contains("--test-render") {
    try VideoView(metalPreview: true).verifyRendering()
    exit(0)
}

if CommandLine.arguments.contains("--test-modes") { verifyModePolicy(); exit(0) }

if CommandLine.arguments.contains("--inspect") {
    let videos = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
    let audios = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    func describe(_ device: AVCaptureDevice) -> [String: Any] {
        return ["name": device.localizedName, "model": device.modelID, "transportType": device.transportType,
                "connected": device.isConnected, "suspended": device.isSuspended,
                "formats": device.formats.map { format -> [String: Any] in
                    let description = format.formatDescription
                    if CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
                       let audio = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                        return ["sampleRate": audio.mSampleRate, "channels": audio.mChannelsPerFrame, "bitsPerChannel": audio.mBitsPerChannel]
                    }
                    let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                    let subtype = CMFormatDescriptionGetMediaSubType(description)
                    let fourCC = String(bytes: [UInt8((subtype >> 24) & 255), UInt8((subtype >> 16) & 255), UInt8((subtype >> 8) & 255), UInt8(subtype & 255)], encoding: .ascii) ?? "unknown"
                    return ["width": dimensions.width, "height": dimensions.height, "pixelFormat": fourCC,
                            "frameRates": format.videoSupportedFrameRateRanges.map { ["min": $0.minFrameRate, "max": $0.maxFrameRate] }]
                }]
    }
    let report: [String: Any] = ["video": videos.map(describe),
                               "audio": audios.filter { $0.localizedName.uppercased().contains("UGREEN") }.map(describe)]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
do {
    let player = try Player(nativePlayer: true)
    app.delegate = player
    withExtendedLifetime(player) { app.run() }
} catch {
    let alert = NSAlert()
    alert.messageText = "Xbox Player could not start"
    alert.informativeText = error.localizedDescription
    alert.runModal()
    exit(1)
}
