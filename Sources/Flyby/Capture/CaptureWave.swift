import AppKit
import MetalKit
import QuartzCore
import os

private let waveLog = Logger(subsystem: "com.fringecore.flyby", category: "capture")

/// The wave that crosses the screen as a screenshot is taken — AirDrop's,
/// more or less: a ring of light spreads out from Flyby's bar, where the
/// screenshot goes, and the screen refracts as it passes.
///
/// A borderless window over the whole display shows the screenshot just
/// taken, bent by a fragment shader, then fades back into the live screen.
/// It never takes a click. With Reduce Motion there's no movement at all: the
/// captured window flashes once, softly.
///
/// The shader is compiled from source when first needed (`prewarm()`), so
/// the build needs no Metal toolchain.
@MainActor
final class CaptureWave: NSObject, MTKViewDelegate {
    /// How long the ring takes to cross the display.
    nonisolated static let duration: CFTimeInterval = 0.9
    private static let fadeOut: CFTimeInterval = 0.12

    private static var sharedPipeline: MTLRenderPipelineState?
    private static var device: MTLDevice? = MTLCreateSystemDefaultDevice()

    private static var playing: CaptureWave?

    private let window: NSWindow
    private let view: MTKView
    private let texture: MTLTexture
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var uniforms: Uniforms
    private var start: CFTimeInterval = 0
    private var finished = false
    private var completion: (() -> Void)?

    /// Matches `WaveUniforms` in the shader, field for field.
    private struct Uniforms {
        var size: SIMD2<Float>
        var origin: SIMD2<Float>
        var time: Float
        var duration: Float
        var reach: Float
        var reduceMotion: Float
        /// The captured window, `x, y, width, height`, in the same space as `origin`.
        var focus: SIMD4<Float>
    }

    /// Compiles the shader ahead of the first capture, off the main thread.
    static func prewarm() {
        guard sharedPipeline == nil, let device else { return }
        device.makeLibrary(source: shaderSource, options: nil) { library, error in
            guard let library else {
                waveLog.error("Wave shader didn't compile: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                return
            }
            let pipeline = makePipeline(device: device, library: library)
            Task { @MainActor in
                if sharedPipeline == nil { sharedPipeline = pipeline }
            }
        }
    }

    /// Plays the wave over `screen`, showing `image` — that display as it
    /// was just captured, without Flyby on it. The ring starts at `origin`,
    /// in screen coordinates; `focus` is the captured window, which flashes
    /// instead under Reduce Motion. The overlay is at `level`, over the menu
    /// bar and the Dock too; anything meant to stay in front has to be above
    /// it. `completion` runs once the live screen is back.
    static func play(
        over screen: NSScreen,
        showing image: CGImage,
        from origin: CGPoint,
        focus: CGRect,
        level: NSWindow.Level = .screenSaver,
        completion: (() -> Void)? = nil
    ) {
        playing?.finish(immediately: true)
        guard let device, let pipeline = pipeline(device: device) else {
            completion?()
            return
        }
        let loader = MTKTextureLoader(device: device)
        guard let queue = device.makeCommandQueue(),
              let texture = try? loader.newTexture(cgImage: image, options: [
                  .SRGB: false,
                  .origin: MTKTextureLoader.Origin.topLeft,
                  .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                  .textureStorageMode: MTLStorageMode.private.rawValue,
              ]) else {
            waveLog.error("Couldn't load the screenshot for the wave")
            completion?()
            return
        }
        let wave = CaptureWave(
            screen: screen, image: image, texture: texture, origin: origin, focus: focus,
            level: level, device: device, queue: queue, pipeline: pipeline
        )
        wave.completion = completion
        playing = wave
        wave.begin()
    }

    private init(
        screen: NSScreen, image: CGImage, texture: MTLTexture, origin start: CGPoint, focus: CGRect,
        level: NSWindow.Level, device: MTLDevice, queue: MTLCommandQueue,
        pipeline: MTLRenderPipelineState
    ) {
        self.texture = texture
        self.queue = queue
        self.pipeline = pipeline

        let frame = screen.frame
        // Top-left origin, in points: the shader's space.
        let local = CGRect(
            x: focus.minX - frame.minX,
            y: frame.maxY - focus.maxY,
            width: focus.width,
            height: focus.height
        ).intersection(CGRect(origin: .zero, size: frame.size))
        let origin = CGPoint(x: start.x - frame.minX, y: frame.maxY - start.y)
        // Far enough that the band has fully left the farthest corner.
        let corners = [CGPoint.zero, CGPoint(x: frame.width, y: 0),
                       CGPoint(x: 0, y: frame.height), CGPoint(x: frame.width, y: frame.height)]
        let reach = corners.map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? frame.width
        let focusRect = local.isNull ? CGRect(origin: .zero, size: frame.size) : local
        uniforms = Uniforms(
            size: SIMD2(Float(frame.width), Float(frame.height)),
            origin: SIMD2(Float(origin.x), Float(origin.y)),
            time: 0,
            duration: Float(Self.duration),
            reach: Float(reach) + 320,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0,
            focus: SIMD4(Float(focusRect.minX), Float(focusRect.minY), Float(focusRect.width), Float(focusRect.height))
        )

        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.setFrame(frame, display: false)
        window.level = level
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        view = MTKView(frame: CGRect(origin: .zero, size: frame.size), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 120
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        if let layer = view.layer as? CAMetalLayer {
            // The screenshot's own colour space, so the overlay matches the
            // screen underneath it exactly.
            layer.colorspace = image.colorSpace
            layer.isOpaque = true
        }
        super.init()
        view.delegate = self
        window.contentView = view
    }

    private func begin() {
        // One frame drawn before the window shows, so it never flashes empty.
        uniforms.time = 0
        view.draw()
        window.orderFrontRegardless()
        start = CACurrentMediaTime()
        view.isPaused = false
    }

    private func finish(immediately: Bool) {
        guard !finished else { return }
        finished = true
        view.isPaused = true
        let done = { [self] in
            window.orderOut(nil)
            view.delegate = nil
            if Self.playing === self { Self.playing = nil }
            completion?()
            completion = nil
        }
        if immediately {
            done()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { done() } })
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render() }
    }

    private func render() {
        if start > 0 {
            uniforms.time = Float(CACurrentMediaTime() - start)
        }
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        var u = uniforms
        encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()

        if start > 0, CACurrentMediaTime() - start >= Self.duration {
            finish(immediately: false)
        }
    }

    // MARK: - Shader

    private static func pipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        if let sharedPipeline { return sharedPipeline }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            sharedPipeline = makePipeline(device: device, library: library)
        } catch {
            waveLog.error("Wave shader didn't compile: \(error.localizedDescription, privacy: .public)")
        }
        return sharedPipeline
    }

    nonisolated private static func makePipeline(device: MTLDevice, library: MTLLibrary) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "waveVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "waveFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            waveLog.error("Wave pipeline failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Everything in points with a top-left origin. The ring's band is a
    /// gaussian around its front; the screen under it is displaced along the
    /// radius by the gaussian's derivative, which reads as refraction — the
    /// band lifts what's inside it and presses on what's ahead. The three
    /// channels are displaced by slightly different amounts at the front for
    /// a thin prismatic edge.
    nonisolated static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct WaveUniforms {
        float2 size;
        float2 origin;
        float time;
        float duration;
        float reach;
        float reduceMotion;
        float4 focus;
    };

    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VOut waveVertex(uint vid [[vertex_id]]) {
        // One triangle that covers the screen.
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut out;
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        out.uv = float2(p.x, 1.0 - p.y);
        return out;
    }

    static float easeOut(float t) { return 1.0 - pow(1.0 - t, 1.25); }

    fragment float4 waveFragment(VOut in [[stage_in]],
                                 texture2d<float> screen [[texture(0)]],
                                 constant WaveUniforms &u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 pos = in.uv * u.size;
        float progress = clamp(u.time / u.duration, 0.0, 1.0);

        if (u.reduceMotion > 0.5) {
            // A soft flash over the captured window, and nothing moves.
            float4 base = screen.sample(s, in.uv);
            float2 lo = u.focus.xy, hi = u.focus.xy + u.focus.zw;
            float inside = step(lo.x, pos.x) * step(pos.x, hi.x) * step(lo.y, pos.y) * step(pos.y, hi.y);
            float flash = inside * 0.22 * (1.0 - smoothstep(0.0, 0.7, progress));
            return float4(base.rgb + flash, 1.0);
        }

        float2 delta = pos - u.origin;
        float dist = length(delta);
        float2 dir = dist > 0.001 ? delta / dist : float2(0.0);

        float front = u.reach * easeOut(progress);
        // The band widens and weakens as it travels, and is gone by the end.
        float width = mix(130.0, 340.0, progress);
        float x = (dist - front) / width;
        float fade = (1.0 - smoothstep(0.5, 1.0, progress)) * smoothstep(0.0, 0.06, progress);
        float band = exp(-x * x * 1.6);

        // Refraction: outward inside the band's trailing half, inward ahead.
        // It grows with the ring, so the small ring at the start doesn't
        // turn the captured window to jelly.
        float strength = 42.0 * smoothstep(40.0, 520.0, front);
        float amount = strength * fade * (-x) * band;
        float2 offset = dir * amount;
        float split = 0.10 * band * fade;
        float r = screen.sample(s, (pos - offset * (1.0 + split)) / u.size).r;
        float g = screen.sample(s, (pos - offset) / u.size).g;
        float b = screen.sample(s, (pos - offset * (1.0 - split)) / u.size).b;
        float3 color = float3(r, g, b);

        // Light: mostly white, with a faint iridescence that turns around
        // the ring, brightest on the front edge.
        float angle = atan2(delta.y, delta.x);
        float3 tint = 0.5 + 0.5 * cos(angle * 2.0 + u.time * 2.5 + float3(0.0, 2.1, 4.2));
        float3 light = mix(float3(1.0), tint, 0.12);
        float edge = exp(-(x - 0.35) * (x - 0.35) * 9.0);
        color += light * (band * 0.16 + edge * 0.20) * fade;

        // The screen behind the wave is lit a touch, and settles.
        float wake = (1.0 - smoothstep(-3.5, 0.0, x)) * 0.03 * fade;
        color += wake;

        return float4(color, 1.0);
    }
    """
}
