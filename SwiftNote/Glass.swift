//
//  Glass.swift
//  SwiftNote — liquid glass (Apple's native API on macOS 26+), frosted glass fallback,
//  shared card / button styles and the audio waveform.
//

import SwiftUI
import AppKit

// MARK: - Frosted material (AppKit)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.state = .active
        v.material = material
        v.blendingMode = blending
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

// MARK: - Capability checks
enum GlassSupport {
    /// True when the app was built with the macOS 26 SDK and is running on macOS 26 or later.
    static var liquidAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

// MARK: - App background (liquid / frosted / solid)
struct AppBackground: View {
    @ObservedObject private var settings = AppSettings.shared
    var cornerRadius: CGFloat? = nil

    var body: some View {
        let radius = cornerRadius ?? CGFloat(settings.glassCornerRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if GlassSupport.reduceTransparency || settings.backgroundStyle == .solid {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else if settings.backgroundStyle == .liquid && GlassSupport.liquidAvailable {
                liquid(shape)
            } else {
                frosted(shape)
            }
        }
    }

    @ViewBuilder
    private func frosted(_ shape: RoundedRectangle) -> some View {
        ZStack {
            VisualEffectView(material: settings.frostedMaterial.material)
                .opacity(settings.glassOpacity)
            if settings.accentTintGlass {
                Rectangle().fill(settings.accentColor.opacity(settings.glassTint))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    @ViewBuilder
    private func liquid(_ shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(liquidStyle(), in: shape).opacity(settings.glassOpacity)
        } else {
            frosted(shape)
        }
        #else
        frosted(shape)
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func liquidStyle() -> Glass {
        var g: Glass = settings.liquidClear ? Glass.clear : Glass.regular
        if settings.accentTintGlass, settings.glassTint > 0.005 {
            g = g.tint(settings.accentColor.opacity(min(0.6, settings.glassTint * 3)))
        }
        return g
    }
    #endif
}

// MARK: - Glass for small controls (tab bar, action buttons)
extension View {
    /// Native liquid glass on macOS 26 when the app is in Liquid Glass mode; a soft translucent fill otherwise.
    @ViewBuilder
    func glassControl<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), AppSettings.shared.glassControls,
           AppSettings.shared.backgroundStyle == .liquid, !GlassSupport.reduceTransparency {
            self.glassEffect(controlGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.softFill(in: shape, tint: tint)
        }
        #else
        self.softFill(in: shape, tint: tint)
        #endif
    }

    func softFill<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        self
            .background(shape.fill((tint ?? Color.primary).opacity(tint == nil ? 0.07 : 0.14)))
            .overlay(shape.strokeBorder((tint ?? Color.primary).opacity(tint == nil ? 0.10 : 0.30), lineWidth: 0.5))
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private func controlGlass(tint: Color?, interactive: Bool) -> Glass {
    var g: Glass = Glass.regular
    if let t = tint { g = g.tint(t.opacity(0.35)) }
    if interactive { g = g.interactive() }
    return g
}
#endif

// MARK: - Shared building blocks
struct Card<Content: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.primary.opacity(settings.cardOpacity)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

struct SoftButtonStyle: ButtonStyle {
    var tint: Color
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Color.white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(shape.fill(prominent ? tint : tint.opacity(configuration.isPressed ? 0.28 : 0.14)))
            .overlay(shape.strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct IconButtonStyle: ButtonStyle {
    var tint: Color = .secondary
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.0)))
            .contentShape(Circle())
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

// MARK: - Waveform (fixed-size Canvas so it can never disturb the toolbar layout)
struct WaveformView: View {
    let levels: [CGFloat]
    var color: Color = .red
    var width: CGFloat = 84
    var height: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let count = max(levels.count, 1)
            let gap: CGFloat = 1.5
            let barWidth = max(1.5, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            var x: CGFloat = 0
            for level in levels {
                let clamped = min(max(level, 0), 1)
                let h = max(3, size.height * clamped)
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color.opacity(0.9)))
                x += barWidth + gap
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}
