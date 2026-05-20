import Foundation

public struct RecentDen: Identifiable, Codable, Sendable {
    public let id: UUID
    public let closedAt: Date
    public let paths: [String]

    public init(id: UUID = UUID(), closedAt: Date = Date(), paths: [String]) {
        self.id = id
        self.closedAt = closedAt
        self.paths = paths
    }

    public var urls: [URL] { paths.map { URL(fileURLWithPath: $0) } }

    public var title: String {
        guard let first = paths.first else { return "Empty" }
        let firstName = (first as NSString).lastPathComponent
        if paths.count == 1 { return firstName }
        return "\(firstName) + \(paths.count - 1)"
    }
}

public final class RecentDensStore {
    public static let shared = RecentDensStore()

    private let defaultsKey = "FileDen.recentDens"
    private let maxRecents = 10

    private init() {}

    public private(set) var all: [RecentDen] {
        get {
            guard let data = UserDefaults.standard.data(forKey: defaultsKey),
                  let list = try? JSONDecoder().decode([RecentDen].self, from: data)
            else { return [] }
            return list
        }
        set {
            let trimmed = Array(newValue.prefix(maxRecents))
            guard let data = try? JSONEncoder().encode(trimmed) else { return }
            UserDefaults.standard.set(data, forKey: defaultsKey)
            NotificationCenter.default.post(name: .recentDensChanged, object: nil)
        }
    }

    public func record(urls: [URL]) {
        let paths = urls.map(\.path).filter { !$0.isEmpty }
        guard !paths.isEmpty else { return }
        var list = all
        list.insert(RecentDen(paths: paths), at: 0)
        all = list
    }

    public func remove(id: UUID) {
        all = all.filter { $0.id != id }
    }

    public func clear() {
        all = []
    }
}

public extension Notification.Name {
    static let recentDensChanged = Notification.Name("recentDensChanged")
}
