import Foundation

struct Clip: Codable {
    let text: String
    let copiedAt: Date
}

final class History {
    enum Tab {
        case recent
        case favorites
    }

    private static let capacity = 100
    private let file: URL
    private let favoritesFile: URL
    private var favoritesLoaded = false
    private(set) var clips: [Clip] = []
    private var favorites: [Clip] = []

    init(file: URL) {
        self.file = file
        favoritesFile = file.deletingLastPathComponent().appending(path: "favorites.json")
    }

    func load() throws {
        clips = Array(try read(from: file).prefix(Self.capacity))
    }

    func loadFavorites() throws {
        favorites = try read(from: favoritesFile)
        favoritesLoaded = true
    }

    private func read(from file: URL) throws -> [Clip] {
        do {
            return try JSONDecoder().decode([Clip].self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    func record(_ text: String, at date: Date = Date()) throws {
        guard !text.isEmpty else { return }
        clips.insert(Clip(text: text, copiedAt: date), at: 0)
        if clips.count > Self.capacity {
            clips.removeLast()
        }
        try save(clips, to: file)
    }

    func clear() throws {
        try save([], to: file)
        clips = []
    }

    func isFavorite(_ clip: Clip) -> Bool {
        favorites.contains { $0.text.utf8.elementsEqual(clip.text.utf8) }
    }

    func addFavorite(_ clip: Clip) throws {
        guard clips.contains(where: {
            $0.copiedAt == clip.copiedAt && $0.text.utf8.elementsEqual(clip.text.utf8)
        }) else { return }
        if !favoritesLoaded { try loadFavorites() }
        guard !isFavorite(clip) else { return }

        let updated = [clip] + favorites
        try save(updated, to: favoritesFile)
        favorites = updated
    }

    func search(_ query: String, in tab: Tab = .recent) -> [Clip] {
        let entries = tab == .recent ? clips : favorites
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.range(of: query, options: .caseInsensitive) != nil }
    }

    private func save(_ clips: [Clip], to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(clips).write(to: file, options: .atomic)
    }
}
