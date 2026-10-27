import EventKit
import SwiftUI

@MainActor
final class CalendarFeed: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let color: Color
        let link: URL?
    }

    @Published private(set) var items: [Item] = []
    // The call to join: one with a link that starts within 10 minutes or began less than 10 minutes ago.
    @Published private(set) var meeting: Item?
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)
    var onNotice: ((Notice) -> Void)?
    private let store = EKEventStore()
    private var reminded: Set<String> = []
    private var timer: Timer?

    var authorized: Bool { status == .fullAccess }

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        if authorized { begin() }
    }

    // Asked only when someone taps Connect, never at launch.
    func connect() {
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            status = EKEventStore.authorizationStatus(for: .event)
            if granted { begin() }
        }
    }

    private func begin() {
        reload()
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        t.tolerance = 5
        timer = t
        check()
    }

    func reload() {
        guard authorized else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600),
                                                 end: now.addingTimeInterval(24 * 3600), calendars: nil)
        items = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { e in
                Item(id: "\(e.calendarItemIdentifier)-\(e.startDate.timeIntervalSince1970)", title: e.title ?? "Untitled",
                     start: e.startDate, end: e.endDate, color: Color(nsColor: e.calendar.color), link: Self.meetingLink(e))
            }
    }

    private func check() {
        let now = Date()
        if items.contains(where: { $0.end <= now }) { reload() }
        let next = items.first { $0.link != nil && $0.start.timeIntervalSince(now) < 600 && now.timeIntervalSince($0.start) < 600 }
        if next?.id != meeting?.id { meeting = next }
        for item in items where !reminded.contains(item.id) {
            let minutes = item.start.timeIntervalSince(now) / 60
            guard minutes > 0, minutes <= 5 else { continue }
            reminded.insert(item.id)
            onNotice?(Notice(icon: "calendar", color: Theme.amber, left: "In \(Int(minutes.rounded(.up))) min",
                             right: item.title, duration: 8))
        }
    }

    // The days of a month that have something on, for the dots under the month view.
    func eventDays(in month: Date) -> Set<Int> {
        guard authorized, let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return Set(store.events(matching: predicate).map { Calendar.current.component(.day, from: $0.startDate) })
    }

    // Opens the call in its own app when that's installed (Zoom, Teams), in the browser otherwise.
    func join(_ item: Item) {
        guard let link = item.link else { return }
        NSWorkspace.shared.open(Self.appLink(link) ?? link)
    }

    // The services MeetingBar recognises in an invitation's URL, location or notes.
    private static let hosts = [
        #"([a-z0-9-]+\.)?zoom(gov)?\.us/(j|my|w)/"#, #"meet\.google\.com/"#, #"teams\.(microsoft|live)\.com/"#,
        #"([a-z0-9-]+\.)?webex\.com/"#, #"whereby\.com/"#, #"meet\.jit\.si/"#, #"(meet\.goto|global\.gotomeeting)\.com/"#,
        #"chime\.aws/"#, #"([a-z0-9-]+\.)?bluejeans\.com/"#, #"discord\.(gg|com/channels)/"#, #"app\.slack\.com/huddle/"#,
        #"facetime\.apple\.com/join"#, #"join\.skype\.com/"#, #"meeting\.zoho\.(com|eu|in)/"#, #"([a-z0-9-]+\.)?larksuite\.com/"#,
        #"app\.gather\.town/"#, #"around\.co/"#, #"app\.livestorm\.co/"#, #"(meetings|v)\.ringcentral\.com/"#,
    ]

    private static func meetingLink(_ event: EKEvent) -> URL? {
        let text = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        let pattern = #"https://(\#(hosts.joined(separator: "|")))[^\s<>"]*"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return URL(string: String(text[range]))
    }

    private static func appLink(_ link: URL) -> URL? {
        let text = link.absoluteString
        var candidate: URL?
        if let host = link.host, host.hasSuffix("zoom.us"), link.path.hasPrefix("/j/") {
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = "zoom.us"
            components.path = "/join"
            components.queryItems = [URLQueryItem(name: "confno", value: link.lastPathComponent)]
                + (URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "pwd" } ?? [])
            candidate = components.url
        } else if text.hasPrefix("https://teams.microsoft.com") {
            candidate = URL(string: "msteams:" + text.dropFirst("https://teams.microsoft.com".count))
        }
        guard let candidate, NSWorkspace.shared.urlForApplication(toOpen: candidate) != nil else { return nil }
        return candidate
    }
}
