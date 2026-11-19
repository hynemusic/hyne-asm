import AppKit
import SwiftUI
import HMLauncherCore

/// The welcome window for new users: five steps, each ticking itself off when it really works.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let onOpenSettings: (Int?) -> Void
    private var window: NSWindow?

    /// `onOpenSettings(page)` opens Settings, on that page if given (2 = LES Import).
    init(model: AppModel, onOpenSettings: @escaping (Int?) -> Void) {
        self.model = model
        self.onOpenSettings = onOpenSettings
    }

    func show(step: OnboardingStep = .welcome) {
        window?.close()
        let view = OnboardingView(model: model, step: step,
                                  onOpenSettings: { [weak self] page in self?.onOpenSettings(page) },
                                  onClose: { [weak self] in self?.window?.close() })
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = Loc.t("Willkommen bei HYNE ASM", "Welcome to HYNE ASM")
        w.setContentSize(NSSize(width: 580, height: 500))
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func snapshot(to url: URL) {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Closing at any step counts as done: the window never comes back by itself.
    func windowWillClose(_ notification: Notification) {
        if !model.config.onboardingDone { model.config.onboardingDone = true }
        if NSApp.windows.filter({ $0.isVisible && $0 !== window && $0.styleMask.contains(.titled) }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State var step: OnboardingStep
    let onOpenSettings: (Int?) -> Void
    let onClose: () -> Void

    @State private var permission = Permissions.isTrusted
    @State private var menuChosen = false
    @State private var menuNote: String?
    @State private var finished = false
    @State private var installError: String?
    @State private var scriptInstalled = FileManager.default.fileExists(atPath: ScriptInstaller.targetURL.path)
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var status: OnboardingStatus {
        var s = OnboardingStatus()
        s.permission = permission
        s.scriptInstalled = scriptInstalled
        s.connected = model.isConnected
        s.panelOpened = model.panelOpened
        s.menuChosen = menuChosen || model.config.categories.contains { !$0.entries.isEmpty }
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if finished { doneScreen } else {
                    switch step {
                    case .welcome: welcome
                    case .permission: permissionStep
                    case .connect: connectStep
                    case .menu: menuStep
                    case .tryIt: tryStep
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            if !finished { footer }
        }
        .frame(width: 580, height: 500)
        .background(DS.canvas)
        .themedColorScheme()
        .foregroundColor(DS.textPrimary)
        .onReceive(poll) { _ in
            if step == .permission { permission = Permissions.isTrusted }
            if step == .connect { scriptInstalled = FileManager.default.fileExists(atPath: ScriptInstaller.targetURL.path) }
        }
    }

    // MARK: Frame

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue || finished ? Color.accent : DS.textTertiary.opacity(0.35))
                        .frame(width: s == step && !finished ? 22 : 8, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: step)
            Text(finished ? Loc.t("Fertig", "All set")
                          : Loc.t("Schritt \(step.rawValue + 1) von 5", "Step \(step.rawValue + 1) of 5"))
                .font(DS.Font.caption).foregroundColor(DS.textTertiary)
        }
        .padding(.top, 40)
        .padding(.bottom, DS.Space.l)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button(Loc.t("Zurück", "Back")) { go(-1) }
            }
            Spacer()
            if !status.isDone(step) {
                Button(Loc.t("Überspringen", "Skip")) { go(1) }.buttonStyle(.borderless).foregroundColor(DS.textTertiary)
            }
            Button(step == .tryIt ? Loc.t("Fertig", "Done") : Loc.t("Weiter", "Continue")) { go(1) }
                .buttonStyle(.borderedProminent).tint(.brandBlue)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .hairline(.top)
    }

    private func go(_ delta: Int) {
        if delta > 0, step == .tryIt { finished = true; return }
        guard let next = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeOut(duration: 0.18)) { step = next }
        if next == .permission { permission = Permissions.isTrusted }
    }

    private func title(_ text: String, _ sub: String) -> some View {
        VStack(spacing: 8) {
            Text(text).font(DS.Font.pageTitle).multilineTextAlignment(.center)
            Text(sub).font(DS.Font.body).foregroundColor(DS.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tick(_ done: Bool, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? DS.success : DS.textTertiary)
            Text(text).font(DS.Font.body).foregroundColor(done ? DS.textSecondary : DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Steps

    private var quickSearchKey: String {
        model.config.shortcuts.quickSearch.first.map(KeyNames.describe) ?? "⌃Space"
    }

    private var welcome: some View {
        VStack(spacing: 26) {
            title(Loc.t("Willkommen bei HYNE ASM", "Welcome to HYNE ASM"),
                  Loc.t("Plugins, Presets und Live-Befehle in Sekunden einfügen – ohne Live's Browser.",
                        "Insert plugins, presets and Live commands in seconds – without Live's browser."))
            HStack(alignment: .top, spacing: 18) {
                feature(PanelPicture(), Loc.t("Panel", "Panel"),
                        Loc.t("Doppelter Rechtsklick in Live öffnet dein Menü an der Maus.",
                              "Double right-click in Live opens your menu at the pointer."))
                feature(SearchPicture(key: quickSearchKey), Loc.t("Schnellsuche", "Quick search"),
                        Loc.t("\(quickSearchKey) und tippen: findet alles, was Live kennt.",
                              "\(quickSearchKey) and type: finds everything Live knows."))
            }
        }
    }

    private func feature<P: View>(_ picture: P, _ name: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            picture.frame(height: 120).frame(maxWidth: .infinity)
                .plate(lit: false, radius: DS.Radius.l, filled: true)
            Text(name).font(DS.Font.bodyStrong)
            Text(text).font(DS.Font.caption).foregroundColor(DS.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionStep: some View {
        VStack(spacing: 24) {
            title(Loc.t("Bedienungshilfen erlauben", "Allow Accessibility"),
                  Loc.t("Damit HYNE ASM den doppelten Rechtsklick und deine Tastenkürzel in Live bemerkt. Es liest nichts anderes mit.",
                        "So HYNE ASM notices the double right-click and your shortcuts in Live. It reads nothing else."))
            Image(systemName: permission ? "checkmark.shield.fill" : "hand.raised.fill")
                .font(.system(size: 44)).foregroundColor(permission ? DS.success : .accent)
                .animation(.easeOut, value: permission)
            if permission {
                Text(Loc.t("Erlaubt – weiter geht's.", "Allowed – on we go.")).font(DS.Font.bodyStrong).foregroundColor(DS.success)
            } else {
                Button(Loc.t("Systemeinstellungen öffnen", "Open System Settings")) {
                    Permissions.prompt()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent).tint(.brandBlue)
                HintText(text: Loc.t("Schalte dort „HYNE Ableton Shortcuts Manager“ ein. Dieser Schritt hakt sich dann selbst ab.",
                                     "Switch on “HYNE Ableton Shortcuts Manager” there. This step ticks itself off."))
            }
        }
    }

    private var connectStep: some View {
        VStack(spacing: 22) {
            title(Loc.t("Mit Live verbinden", "Connect Live"),
                  Loc.t("Das kleine Live-Script ASMbridge setzt deine Auswahl in Live ein.",
                        "The small Live script ASMbridge puts what you pick into Live."))
            ConnectionLine(connected: status.connected)
                .frame(height: 56)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    tick(status.scriptInstalled, Loc.t("ASMbridge installieren", "Install ASMbridge"))
                    Button(status.scriptInstalled ? Loc.t("Neu installieren", "Reinstall") : Loc.t("Installieren", "Install")) { install() }
                        .controlSize(.small)
                }
                tick(status.connected, Loc.t("Live neu starten", "Restart Live"))
                tick(status.connected, Loc.t("In Live: Einstellungen → Link, Tempo & MIDI → Control Surface: ASMbridge",
                                             "In Live: Settings → Link, Tempo & MIDI → Control Surface: ASMbridge"))
                if let installError {
                    Text(installError).font(DS.Font.caption).foregroundColor(DS.warning)
                }
            }
            .padding(DS.Space.l)
            .dsCard(padding: 0)
            Text(status.connected
                 ? Loc.t("● Verbunden mit Live \(model.liveVersion ?? "")", "● Connected to Live \(model.liveVersion ?? "")")
                 : Loc.t("Warte auf Live …", "Waiting for Live …"))
                .font(DS.Font.bodyStrong)
                .foregroundColor(status.connected ? DS.success : DS.textTertiary)
        }
    }

    private func install() {
        do {
            try ScriptInstaller.install()
            installError = nil
            scriptInstalled = true
        } catch {
            installError = Loc.t("Installation fehlgeschlagen: \(error.localizedDescription)", "Installation failed: \(error.localizedDescription)")
        }
    }

    private var menuStep: some View {
        VStack(spacing: 22) {
            title(Loc.t("Dein Menü", "Your menu"),
                  Loc.t("Womit soll das Panel starten? Alles lässt sich später in den Einstellungen ändern.",
                        "What should the panel start with? You can change everything later in Settings."))
            VStack(spacing: 10) {
                choice("square.dashed", Loc.t("Leer starten", "Start empty"),
                       Loc.t("Du füllst es selbst in den Einstellungen.", "You fill it yourself in Settings.")) {
                    menuChosen = true
                    menuNote = Loc.t("Leg in den Einstellungen los – Doppelklick fügt hinzu.", "Get going in Settings – double-click adds.")
                }
                if FileManager.default.fileExists(atPath: LESMenuParser.defaultURL.path) {
                    choice("square.and.arrow.down", Loc.t("Aus LES übernehmen", "Import from LES"),
                           Loc.t("Dein Menü aus Live Enhancement Suite, mit Vorschau.", "Your Live Enhancement Suite menu, with a preview.")) {
                        menuChosen = true
                        onOpenSettings(2)
                    }
                }
                choice("star", Loc.t("Startset", "Starter set"),
                       Loc.t("Live's eigene Devices: EQ Eight, Compressor, Reverb, Drift …", "Live's own devices: EQ Eight, Compressor, Reverb, Drift …")) {
                    let n = model.config.addStarterSet(from: model.catalog.items)
                    menuChosen = true
                    menuNote = n > 0 ? Loc.t("\(n) Devices hinzugefügt.", "\(n) devices added.")
                        : Loc.t("Nichts Neues – Live noch nicht verbunden oder schon drin.", "Nothing new – Live not connected yet, or already there.")
                }
            }
            if let menuNote { Text(menuNote).font(DS.Font.caption).foregroundColor(DS.success) }
        }
    }

    private func choice(_ symbol: String, _ name: String, _ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundColor(.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                    Text(text).font(DS.Font.caption).foregroundColor(DS.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(DS.textTertiary)
            }
            .padding(.horizontal, DS.Space.m)
            .frame(height: 52)
            .plate(lit: false, radius: DS.Radius.m, filled: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tryStep: some View {
        VStack(spacing: 24) {
            title(Loc.t("Probier's aus", "Try it"),
                  Loc.t("Geh in Live und mach einen doppelten Rechtsklick – irgendwo im Set.",
                        "Go to Live and double right-click – anywhere in the set."))
            Image(systemName: model.panelOpened ? "checkmark.circle.fill" : "cursorarrow.click.2")
                .font(.system(size: 48))
                .foregroundColor(model.panelOpened ? DS.success : .accent)
                .animation(.easeOut, value: model.panelOpened)
            Text(model.panelOpened ? Loc.t("Das Panel ist aufgegangen. Klick ein Plugin, um es einzufügen.", "The panel opened. Click a plugin to insert it.")
                                   : Loc.t("Warte auf den Doppelklick …", "Waiting for the double right-click …"))
                .font(DS.Font.bodyStrong)
                .foregroundColor(model.panelOpened ? DS.success : DS.textTertiary)
        }
    }

    private var doneScreen: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 52)).foregroundColor(DS.success)
            title(Loc.t("Alles bereit", "You're all set"),
                  Loc.t("Tipp: Halte ⇧, um mehrere Dinge nacheinander einzufügen. Die Einführung findest du jederzeit im Menüleisten-Menü.",
                        "Tip: hold ⇧ to insert several things in a row. The introduction is always in the menu bar menu."))
            HStack(spacing: 12) {
                Button(Loc.t("Einstellungen öffnen", "Open Settings")) { onOpenSettings(nil); onClose() }
                Button(Loc.t("Schließen", "Close")) { onClose() }
                    .buttonStyle(.borderedProminent).tint(.brandBlue).keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Pictures

/// ASM ── Live: grey with a moving shimmer while waiting; fills green and pulses once when connected.
struct ConnectionLine: View {
    let connected: Bool
    @State private var shimmer: CGFloat = 0
    @State private var fill: CGFloat = 0
    @State private var pulse = false
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        HStack(spacing: 12) {
            node("bolt.horizontal.fill", "ASM", lit: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.raised).frame(height: 4)
                    if !connected && !reduceMotion {
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, DS.textTertiary.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * 0.3, height: 4)
                            .offset(x: (geo.size.width * 1.3) * shimmer - geo.size.width * 0.3)
                    }
                    Capsule().fill(DS.success).frame(width: geo.size.width * fill, height: 4)
                    Circle().fill(DS.success.opacity(pulse ? 0 : 0.35))
                        .frame(width: pulse ? 40 : 6, height: pulse ? 40 : 6)
                        .position(x: geo.size.width, y: geo.size.height / 2)
                }
                .frame(maxHeight: .infinity)
                .clipped()
            }
            node("waveform", "Live", lit: connected)
        }
        .onAppear {
            if connected { fill = 1 }
            startShimmer()
        }
        .onChange(of: connected) { now in
            guard now else {
                // Live dropped (e.g. restarted): back to waiting, ready to pulse again.
                fill = 0
                pulse = false
                startShimmer()
                return
            }
            if reduceMotion { fill = 1; return }
            withAnimation(.easeOut(duration: 0.6)) { fill = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.7)) { pulse = true }
            }
        }
    }

    private func startShimmer() {
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { shimmer = 0 }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { shimmer = 1 }
        }
    }

    private func node(_ symbol: String, _ name: String, lit: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundColor(lit ? (name == "Live" ? DS.success : .accent) : DS.textTertiary)
                .frame(width: 44, height: 36)
                .plate(lit: false, radius: DS.Radius.m, filled: true)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).stroke(lit && name == "Live" ? DS.success : DS.hairline))
            Text(name).font(DS.Font.caption).foregroundColor(DS.textTertiary)
        }
        .animation(.easeOut(duration: 0.3), value: lit)
    }
}

/// A tiny panel whose rows fade in one after the other, next to a pointer.
private struct PanelPicture: View {
    @State private var shown = 0
    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "cursorarrow").font(.system(size: 14)).foregroundColor(DS.textSecondary).padding(.top, 2)
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(i == 0 ? Color.accent : DS.raised).frame(width: 10, height: 10)
                        RoundedRectangle(cornerRadius: 2).fill(DS.textTertiary.opacity(0.5)).frame(width: CGFloat(54 - i * 8), height: 5)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 96, height: 16)
                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.raised.opacity(0.6)))
                    .opacity(i < shown ? 1 : 0)
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 6).fill(DS.canvas))
        }
        .onReceive(timer) { _ in
            withAnimation(.easeOut(duration: 0.2)) { shown = shown >= 6 ? 0 : shown + 1 }
        }
    }
}

/// A search field that types "comp" letter by letter, with the shortcut as a key cap.
private struct SearchPicture: View {
    let key: String
    @State private var typed = 0
    private let word = Array("comp")
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            Text(key).font(DS.Font.keycap).padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(DS.raised))
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundColor(.accent)
                Text(String(word.prefix(min(typed, word.count)))).font(DS.Font.caption)
                Rectangle().fill(Color.accent).frame(width: 1.5, height: 11)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(width: 130, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(DS.canvas))
        }
        .onReceive(timer) { _ in typed = typed >= word.count + 4 ? 0 : typed + 1 }
    }
}
