import Foundation

// A small to-do list. A time at the end of a task ("Call Budi 15:30") makes it due then, and the notch says so.
@MainActor
final class TaskList: ObservableObject {
    struct Item: Codable, Identifiable {
        var id = UUID()
        var title: String
        var due: Date?
        var done = false
    }

    @Published private(set) var items: [Item] = []
    var onNotice: ((Notice) -> Void)?
    private var timer: Timer?

    var open: Int { items.filter { !$0.done }.count }

    init() {
        if let data = UserDefaults.standard.data(forKey: "tasks"),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
        schedule()
    }

    func add(_ text: String) {
        var title = text.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        var due: Date?
        if let range = title.range(of: #"\s(\d{1,2})[:.](\d{2})$"#, options: .regularExpression) {
            let parts = title[range].trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == ":" || $0 == "." })
            if let h = Int(parts[0]), let m = Int(parts[1]), h < 24, m < 60,
               var date = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) {
                if date <= Date() { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date }
                due = date
                title = String(title[..<range.lowerBound])
            }
        }
        items.insert(Item(title: title, due: due), at: 0)
        save()
    }

    func toggle(_ item: Item) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].done.toggle()
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearDone() {
        items.removeAll(where: \.done)
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: "tasks")
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        let now = Date()
        guard let next = items.filter({ !$0.done && ($0.due ?? .distantPast) > now }).min(by: { $0.due! < $1.due! }),
              let due = next.due else { return }
        let t = Timer(fire: due, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onNotice?(Notice(icon: "checklist", color: Theme.amber, left: "Due now", right: next.title,
                                       duration: 8, essential: true))
                self?.schedule()
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
