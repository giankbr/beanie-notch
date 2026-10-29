import SwiftUI

// Switches across the top; screens, batteries and Shortcuts below.
struct ControlsView: View {
    @EnvironmentObject var toggles: QuickToggles
    @EnvironmentObject var displays: Displays
    @EnvironmentObject var battery: BatteryInfo
    @EnvironmentObject var shortcuts: ShortcutsRunner
    @EnvironmentObject var settings: Settings

    var body: some View {
        VStack(spacing: 10) {
            ToggleRow()
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) {
                    DisplaysCard()
                    BatteryCard()
                }
                ShortcutsCard().frame(width: settings.compactPages ? 180 : 210)
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            toggles.refresh()
            displays.refresh()
            battery.refresh()
            if !shortcuts.loaded { shortcuts.load() }
        }
    }
}

private struct ToggleRow: View {
    @EnvironmentObject var toggles: QuickToggles
    @EnvironmentObject var keepAwake: KeepAwake
    @EnvironmentObject var settings: Settings

    var body: some View {
        HStack(spacing: 6) {
            tile("moon.circle.fill", "Dark mode", toggles.darkMode) { toggles.toggleDarkMode() }
            tile("sun.horizon.fill", "Night Shift", toggles.nightShift) { toggles.toggleNightShift() }
            tile("mug.fill", "Keep awake", keepAwake.active) {
                if keepAwake.active { keepAwake.stop() } else { keepAwake.start(minutes: 0) }
            }
            tile(toggles.micMuted ? "mic.slash.fill" : "mic.fill", "Mic muted", toggles.micMuted, color: Theme.red) { toggles.toggleMic() }
            tile("menubar.dock.rectangle", "Hide Dock", toggles.dockHidden) { toggles.toggleDockHidden() }
            tile("macwindow.on.rectangle", "Desktop icons", toggles.desktopIcons) { toggles.toggleDesktopIcons() }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ icon: String, _ title: String, _ on: Bool, color: Color = Theme.accent,
                      action: @escaping () -> Void) -> some View {
        // Icon over the label, or beside it when the panel is short.
        let layout = settings.compactPages ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
        return Button(action: action) {
            layout {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? color : Theme.dim)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(on ? "On" : "Off").font(.app(size: 8.5)).foregroundStyle(on ? color : Theme.faint)
                }
            }
            .padding(settings.compactPages ? 7 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TileFace(on: on, color: color))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: on)
        }
        .buttonStyle(PressStyle())
    }
}

private struct DisplaysCard: View {
    @EnvironmentObject var displays: Displays

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Brightness").font(.app(size: 12, weight: .semibold))
            if displays.screens.isEmpty {
                Text("No screen to adjust").font(.app(size: 9.5)).foregroundStyle(Theme.faint)
            }
            ForEach(displays.screens) { screen in
                HStack(spacing: 8) {
                    Image(systemName: screen.builtIn ? "laptopcomputer" : "display").font(.system(size: 10)).foregroundStyle(Theme.dim)
                        .frame(width: 14)
                    Text(screen.name).font(.app(size: 9.5)).lineLimit(1).frame(width: 96, alignment: .leading)
                    ThemedSlider(value: Binding(get: { Double(screen.level) }, set: { displays.set(screen, .init($0)) }))
                    Text("\(Int((screen.level * 100).rounded()))").font(.mono(size: 9)).foregroundStyle(Theme.faint)
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }
}

private struct BatteryCard: View {
    @EnvironmentObject var battery: BatteryInfo
    @EnvironmentObject var power: PowerMonitor
    @EnvironmentObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Batteries").font(.app(size: 12, weight: .semibold))
                Spacer()
                if power.present {
                    Text([battery.health.map { "Health \($0)%" }, battery.cycles.map { "\($0) cycles" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.mono(size: 8.5)).foregroundStyle(Theme.faint)
                }
            }
            if power.present {
                row(power.charging ? "battery.100percent.bolt" : "laptopcomputer", "This Mac", [("", power.percent)])
            }
            ForEach(battery.devices) { device in
                row(device.name.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "headphones",
                    device.name, device.levels)
            }
            if battery.devices.isEmpty, settings.size != .compact {
                Text("Bluetooth devices that report a charge show up here")
                    .font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func row(_ icon: String, _ name: String, _ levels: [(label: String, percent: Int)]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Theme.dim).frame(width: 14)
            Text(name).font(.app(size: 9.5)).lineLimit(1)
            Spacer(minLength: 6)
            ForEach(levels.indices, id: \.self) { i in
                let level = levels[i]
                HStack(spacing: 3) {
                    if !level.label.isEmpty { Text(level.label).foregroundStyle(Theme.faint) }
                    Text("\(level.percent)%").foregroundStyle(level.percent <= 20 ? Theme.red : Theme.ink)
                }
                .font(.mono(size: 9, weight: .semibold))
            }
        }
    }
}

private struct ShortcutsCard: View {
    @EnvironmentObject var shortcuts: ShortcutsRunner
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? shortcuts.names : shortcuts.names.filter { ClipboardHistory.matches($0, query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Shortcuts").font(.app(size: 12, weight: .semibold))
                Spacer()
                IconButton(icon: "arrow.clockwise") { shortcuts.load() }.help("Reload")
            }
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
                TextField("Find a shortcut", text: $query).textFieldStyle(.plain).font(.app(size: 10))
                    .onSubmit { if let first = filtered.first { shortcuts.run(first) } }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: Theme.round(7), style: .continuous).fill(Theme.ink.opacity(0.06)))
            if !shortcuts.loaded {
                LoadingView(text: "Loading shortcuts…")
            } else if shortcuts.names.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No shortcuts yet").font(.app(size: 9.5)).foregroundStyle(Theme.faint)
                    PillButton(text: "Open Shortcuts", color: Theme.accent) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(filtered, id: \.self) { name in
                            Button { shortcuts.run(name) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: shortcuts.running == name ? "hourglass" : "play.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(shortcuts.running == name ? Theme.amber : Theme.accent)
                                        .frame(width: 12)
                                    Text(name).font(.app(size: 10)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 6)
                                .frame(height: 22)
                                .buttonFace(RoundedRectangle(cornerRadius: Theme.round(6), style: .continuous), Theme.ink.opacity(0.05), quiet: true)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(shortcuts.running != nil)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}
