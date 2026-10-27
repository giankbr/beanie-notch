import SwiftUI

struct PrayerView: View {
    @EnvironmentObject var prayer: PrayerTimes

    var body: some View {
        if let place = prayer.place {
            VStack(spacing: 10) {
                NextPanel(place: place)
                Timeline()
            }
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

// The next prayer with a bar filling from the one before it, and the place with its qibla beside it.
private struct NextPanel: View {
    @EnvironmentObject var prayer: PrayerTimes
    var place: PrayerTimes.Place

    var body: some View {
        HStack(spacing: 14) {
            if let next = prayer.next {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let now = context.date
                    let previous = prayer.today.last { $0.isPrayer && $0.time <= now }?.time ?? Calendar.current.startOfDay(for: now)
                    let span = max(next.time.timeIntervalSince(previous), 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NEXT PRAYER").font(.app(size: 8.5, weight: .semibold)).tracking(0.9).foregroundStyle(Theme.faint)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(prayer.label(next)).font(.app(size: 24, weight: .bold)).foregroundStyle(Theme.accent)
                            Text(next.time.formatted(date: .omitted, time: .shortened)
                                 + (Calendar.current.isDateInTomorrow(next.time) ? " · tomorrow" : ""))
                                .font(.app(size: 15, weight: .semibold)).monospacedDigit()
                            Spacer(minLength: 4)
                            Text(countdown(to: next.time, from: now)).font(.mono(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                        }
                        SegmentMeter(value: min(1, now.timeIntervalSince(previous) / span), color: Theme.accent, segments: 30)
                        Text(prayer.method.title + (prayer.hanafi ? " · Hanafi" : "") + " · since the last prayer")
                            .font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                }
            }
            Rectangle().fill(Theme.stroke).frame(width: 1)
            HStack(spacing: 10) {
                Compass(bearing: place.qibla)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: prayer.locating ? "location.circle" : "location.fill").font(.system(size: 8.5))
                        Text(place.name).font(.app(size: 11, weight: .semibold)).lineLimit(1)
                    }
                    Text("Qibla \(Int(place.qibla.rounded()))° \(place.qiblaDirection)").font(.app(size: 9.5)).foregroundStyle(Theme.dim)
                    CityMenu(label: "Change place").foregroundStyle(Theme.accent)
                    if let error = prayer.locationError {
                        Text(error).font(.app(size: 8.5)).foregroundStyle(Theme.amber).lineLimit(1)
                    }
                }
            }
            .frame(width: 190, alignment: .leading)
        }
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
        .card()
    }

    private func countdown(to time: Date, from now: Date) -> String {
        let minutes = max(0, Int((time.timeIntervalSince(now) / 60).rounded(.up)))
        return minutes >= 60 ? "in \(minutes / 60)h \(minutes % 60)m" : "in \(minutes) min"
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

// The whole day across: each time in its own tile, the next one lit, the ones gone by dimmed.
private struct Timeline: View {
    @EnvironmentObject var prayer: PrayerTimes

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 6) {
                ForEach(prayer.today) { entry in
                    let isNext = entry.time == prayer.next?.time
                    let past = entry.time < context.date
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: Self.symbol(entry.name))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isNext ? Theme.accent : entry.isPrayer ? Theme.dim : Theme.faint)
                        Spacer(minLength: 0)
                        Text(entry.name).font(.app(size: 9.5, weight: .medium)).lineLimit(1)
                            .foregroundStyle(isNext ? Theme.accent : Theme.dim)
                        Text(entry.time.formatted(date: .omitted, time: .shortened))
                            .font(.app(size: 14, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(isNext ? Theme.ink : past ? Theme.faint : Theme.ink)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isNext ? Theme.accent.opacity(0.14) : Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(isNext ? Theme.accent.opacity(0.55) : Theme.stroke))
                    .opacity(past && !isNext ? 0.6 : 1)
                }
            }
        }
    }

    private static func symbol(_ name: String) -> String {
        switch name {
        case "Imsak": "moon.stars.fill"
        case "Subuh", "Fajr": "sun.horizon.fill"
        case "Terbit", "Sunrise": "sunrise.fill"
        case "Dzuhur", "Dhuhr": "sun.max.fill"
        case "Ashar", "Asr": "sun.min.fill"
        case "Maghrib": "sunset.fill"
        case "Isya", "Isha": "moon.fill"
        default: "clock"
        }
    }
}
