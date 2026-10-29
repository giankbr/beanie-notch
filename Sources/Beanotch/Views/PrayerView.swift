import SwiftUI

struct PrayerView: View {
    @EnvironmentObject var prayer: PrayerTimes

    var body: some View {
        if let place = prayer.place {
            SunArcPage(place: place)
        } else {
            Panel {
                Placeholder(icon: "location", title: "Where are you?",
                            caption: "Prayer times are worked out on this Mac from your location, no internet needed") {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            PrimaryButton(text: prayer.locating ? "Locating…" : "Use my location", icon: "location.fill") {
                                prayer.useCurrentLocation()
                            }
                            .frame(width: 170)
                            CityMenu(label: "Pick a city")
                        }
                        if let error = prayer.locationError {
                            Text(error).font(.app(size: 9)).foregroundStyle(Theme.amber)
                        }
                    }
                }
            }
        }
    }
}

struct CityMenu: View {
    @EnvironmentObject var prayer: PrayerTimes
    var label: String

    var body: some View {
        Menu {
            Button("Use my location") { prayer.useCurrentLocation() }
            Divider()
            ForEach(PrayerTimes.cities, id: \.self) { city in
                Button(city.name) { prayer.place = city }
            }
        } label: {
            Text(label).font(.app(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// The day as the sun's path: a dot for each time along an arc that rises at sunrise, peaks at noon and sets at
// Maghrib, the part already gone in the accent and a marker for now. The next prayer and its countdown sit above it,
// the place and the qibla in a corner, and every time under its dot.
private struct SunArcPage: View {
    @EnvironmentObject var prayer: PrayerTimes
    var place: PrayerTimes.Place

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 6) {
                header(now)
                SunArc(entries: prayer.today, next: prayer.next, now: now)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                labels(now)
            }
            .padding(.horizontal, 4)
        }
    }

    private func header(_ now: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let next = prayer.next {
                let fasting = prayer.fasting(at: now)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(prayer.label(next)).font(.app(size: 20, weight: .bold)).foregroundStyle(Theme.accent)
                        Text(countdown(to: next.time, from: now)).font(.app(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
                    }
                    Text(fasting ?? (next.time.formatted(date: .omitted, time: .shortened)
                         + (Calendar.current.isDateInTomorrow(next.time) ? " tomorrow" : "") + " · " + prayer.method.title))
                        .font(.app(size: 9.5)).foregroundStyle(fasting == nil ? Theme.faint : Theme.accent2).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 7) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(place.name) · Qibla \(Int(place.qibla.rounded()))° \(place.qiblaDirection)")
                        .font(.app(size: 10, weight: .semibold)).lineLimit(1)
                    CityMenu(label: "Change place").foregroundStyle(Theme.accent)
                }
                Compass(bearing: place.qibla).scaleEffect(0.66).frame(width: 31, height: 31)
            }
        }
    }

    // Each time under its dot, in even columns, the next one lit and the ones gone by faded.
    private func labels(_ now: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(prayer.today) { entry in
                let isNext = SunArc.isNext(entry, prayer.next)
                VStack(spacing: 0) {
                    Text(prayer.label(entry)).font(.app(size: 8.5, weight: .medium)).lineLimit(1)
                        .foregroundStyle(isNext ? Theme.accent : Theme.dim)
                    Text(entry.time.formatted(date: .omitted, time: .shortened))
                        .font(.app(size: 11, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(isNext ? Theme.ink : entry.time < now ? Theme.faint : Theme.ink.opacity(0.85))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func countdown(to time: Date, from now: Date) -> String {
        let minutes = max(0, Int((time.timeIntervalSince(now) / 60).rounded(.up)))
        return minutes >= 60 ? "in \(minutes / 60)h \(minutes % 60)m" : "in \(minutes) min"
    }
}

// The arc itself. The times sit evenly across (so close ones like Imsak and Fajr don't crowd), each as high as the sun
// is then: above the horizon between sunrise and Maghrib, a little under it before and after.
private struct SunArc: View {
    let entries: [PrayerTimes.Entry]
    let next: PrayerTimes.Entry?
    let now: Date

    // The next one is lit: after Isha that's tomorrow's Fajr, so today's Fajr stands in for it.
    static func isNext(_ entry: PrayerTimes.Entry, _ next: PrayerTimes.Entry?) -> Bool {
        guard let next else { return false }
        return entry.time == next.time || Calendar.current.isDateInTomorrow(next.time) && entry.name == next.name
    }

    var body: some View {
        Canvas { g, size in
            let n = entries.count
            guard n > 1 else { return }
            let horizon = size.height * 0.74, lift = size.height * 0.64, dip = size.height * 0.2
            let rise = entries.first { $0.name == "Sunrise" || $0.name == "Terbit" }?.time
            let set = entries.first { $0.name == "Maghrib" }?.time
            func x(_ position: Double) -> CGFloat { CGFloat((position + 0.5) / Double(n)) * size.width }
            // How high the sun stands: a half sine across the daylight, a shallow dip either side of it.
            func elevation(_ t: Date) -> Double {
                guard let rise, let set, set > rise else { return 0 }
                if t >= rise && t <= set { return sin(.pi * t.timeIntervalSince(rise) / set.timeIntervalSince(rise)) }
                let away = t < rise ? rise.timeIntervalSince(t) : t.timeIntervalSince(set)
                return -min(1, away / 7200)
            }
            // A point on the arc at a position along the row of times, between two of them by time.
            func point(_ position: Double) -> CGPoint {
                let i = min(max(Int(position.rounded(.down)), 0), n - 1), j = min(i + 1, n - 1)
                let f = position - Double(i)
                let t = entries[i].time.addingTimeInterval(entries[j].time.timeIntervalSince(entries[i].time) * f)
                let e = elevation(t)
                return CGPoint(x: x(position), y: horizon - CGFloat(e >= 0 ? e * lift : e * dip))
            }
            // Where now falls along the row.
            let nowAt: Double = {
                guard let k = entries.lastIndex(where: { $0.time <= now }) else { return 0 }
                if k == n - 1 { return Double(n - 1) }
                let span = entries[k + 1].time.timeIntervalSince(entries[k].time)
                return Double(k) + now.timeIntervalSince(entries[k].time) / max(span, 1)
            }()
            func arc(_ a: Double, _ b: Double) -> Path {
                var p = Path()
                let steps = max(2, Int((b - a) * 24))
                for s in 0...steps {
                    let pt = point(a + (b - a) * Double(s) / Double(steps))
                    if s == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                return p
            }

            var line = Path()
            line.move(to: CGPoint(x: 0, y: horizon))
            line.addLine(to: CGPoint(x: size.width, y: horizon))
            g.stroke(line, with: .color(Theme.ink.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            g.stroke(arc(0, Double(n - 1)), with: .color(Theme.ink.opacity(0.16)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            if nowAt > 0 {
                let shading: GraphicsContext.Shading = Theme.gradient
                    ? .linearGradient(Gradient(colors: [Theme.accent, Theme.accent2]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                    : .color(Theme.accent)
                g.stroke(arc(0, nowAt), with: shading, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            for (i, entry) in entries.enumerated() {
                let c = point(Double(i))
                if Self.isNext(entry, next) {
                    g.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)), with: .color(Theme.accent.opacity(0.2)))
                    g.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(Theme.accent))
                } else {
                    let color = entry.time < now ? Theme.accent.opacity(0.7) : Theme.ink.opacity(entry.isPrayer ? 0.45 : 0.25)
                    g.fill(Path(ellipseIn: CGRect(x: c.x - 3.2, y: c.y - 3.2, width: 6.4, height: 6.4)), with: .color(color))
                }
            }
            // Now: the sun while it's up, the moon while it's down.
            let at = point(nowAt)
            let mark = at.y <= horizon ? "sun.max.fill" : "moon.fill"
            g.draw(Text(Image(systemName: mark)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.amber),
                   at: CGPoint(x: at.x, y: at.y - 13))
        }
    }
}

// A small dial: north at the top, the needle pointing to Mecca.
private struct Compass: View {
    var bearing: Double

    var body: some View {
        ZStack {
            Circle().fill(Theme.ink.opacity(0.05))
            Circle().strokeBorder(Theme.stroke)
            ForEach(0..<4) { i in
                Rectangle().fill(Theme.faint).frame(width: 1, height: 4)
                    .offset(y: -19).rotationEffect(.degrees(Double(i) * 90))
            }
            Text("N").font(.app(size: 7, weight: .bold)).foregroundStyle(Theme.faint).offset(y: -13)
            Image(systemName: "location.north.fill").font(.system(size: 13)).foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(bearing))
        }
        .frame(width: 46, height: 46)
    }
}

