import AppKit
import SwiftUI
import HMLauncherCore

/// One small floating label for every tooltip. It is its own window, so it works in the panel while Live is the
/// active app (macOS shows `.help` tooltips only for the active app) and can stick out past a window's edge.
@MainActor
final class TooltipWindow {
    static let shared = TooltipWindow()
    static let delay: TimeInterval = 0.7

    private var panel: NSPanel?
    private var pending: Task<Void, Never>?

    /// Shows `text` below `rect` (screen coordinates) after the delay, unless cancelled first.
    func schedule(_ text: String, below rect: NSRect) {
        cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.show(text, below: rect)
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        panel?.orderOut(nil)
    }

    private func show(_ text: String, below rect: NSRect) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = NSColor(Palette.current.textPrimary)
        label.sizeToFit()
        let size = NSSize(width: ceil(label.frame.width) + 16, height: ceil(label.frame.height) + 8)
        let p = panel ?? NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(Palette.current.panelSurface).withAlphaComponent(0.98).cgColor
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor(Palette.current.panelStroke).cgColor
        label.frame.origin = NSPoint(x: 8, y: 4)
        box.addSubview(label)
        p.contentView = box
        p.setFrame(Self.frame(for: size, below: rect), display: true)
        p.orderFrontRegardless()
        panel = p
    }

    static func frame(for size: NSSize, below rect: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        return TooltipPlacement.frame(size: size, below: rect, visible: screen?.visibleFrame ?? .infinite)
    }
}

extension View {
    /// A short label after resting the pointer on this view for 0.7 s (icon-only controls).
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}

private struct TooltipModifier: ViewModifier {
    let text: String
    @State private var anchor = TooltipAnchor.Box()

    func body(content: Content) -> some View {
        content
            .background(TooltipAnchor(box: anchor))
            .onHover { inside in
                if inside, let rect = anchor.screenRect { TooltipWindow.shared.schedule(text, below: rect) }
                else { TooltipWindow.shared.cancel() }
            }
            .simultaneousGesture(TapGesture().onEnded { TooltipWindow.shared.cancel() })
            .onDisappear { TooltipWindow.shared.cancel() }
            .accessibilityHint(text)
    }
}

/// Reads where the view is on screen when the pointer arrives.
private struct TooltipAnchor: NSViewRepresentable {
    final class Box {
        weak var view: NSView?
        var screenRect: NSRect? {
            guard let view, let window = view.window else { return nil }
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
    }
    let box: Box

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        box.view = v
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) { box.view = nsView }
}
