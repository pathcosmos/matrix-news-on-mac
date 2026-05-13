import Foundation

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

@MainActor
final class NewsViewModel: ObservableObject {
    @Published var settings: ViewerSettings
    @Published var preferences: UserPreferences
    @Published private(set) var allItems: [NewsItem] = []
    @Published private(set) var sourceOptions: [NewsSourceOption] = []
    @Published var selectedItemID: String?
    @Published private(set) var playbackRevision = 0

    private let syncStore = PreferenceSyncStore()
    private let engine = PersonalizationEngine()
    private let dataLoader: NewsDataLoader
    private var preparedNewsRefresh: NewsDataPayload?
    private var isPreparingNewsRefresh = false

    init(dataLoader: NewsDataLoader = .appDefault()) {
        self.dataLoader = dataLoader
        settings = syncStore.loadSettings()
        preferences = syncStore.loadPreferences()
    }

    var rankedItems: [NewsItem] {
        engine.rank(
            allItems,
            preferences: preferences,
            enabledSourceIDs: settings.enabledSourceIDs
        )
    }

    var visibleItems: [NewsItem] {
        Array(rankedItems.prefix(settings.visibleNewsCount))
    }

    var passiveDisplayItems: [NewsItem] {
        Array(Self.newestFirst(allItems).prefix(50))
    }

    var selectedItem: NewsItem? {
        guard let selectedItemID else { return passiveDisplayItems.first }
        return passiveDisplayItems.first { $0.id == selectedItemID } ?? passiveDisplayItems.first
    }

    func load() async {
        let payload = await dataLoader.load()
        apply(payload, restartsPlayback: true)
    }

    func prepareNewsRefreshForNextCycle() async {
        guard !isPreparingNewsRefresh else { return }
        isPreparingNewsRefresh = true
        defer { isPreparingNewsRefresh = false }

        guard let payload = await dataLoader.loadRemote() else {
            return
        }

        let loadedItems = Self.newestFirst(payload.latest.items)
        preparedNewsRefresh = loadedItems == allItems ? nil : payload
    }

    func applyPreparedNewsRefreshIfAvailable() async {
        guard let payload = preparedNewsRefresh else { return }
        preparedNewsRefresh = nil
        apply(payload, restartsPlayback: true)
    }

    private func apply(_ payload: NewsDataPayload, restartsPlayback: Bool) {
        let loadedItems = Self.newestFirst(payload.latest.items)
        let itemsChanged = loadedItems != allItems

        allItems = loadedItems
        sourceOptions = NewsSourceOption.grouped(from: payload.sources)
        settings.reconcileEnabledSources(payload.sources)
        saveSettings()

        if restartsPlayback || itemsChanged {
            selectedItemID = nil
            playbackRevision += 1
        }
    }

    func like(_ item: NewsItem) {
        preferences.like(item)
        selectedItemID = item.id
        savePreferences()
    }

    func save(_ item: NewsItem) {
        preferences.save(item)
        selectedItemID = item.id
        savePreferences()
    }

    func hide(_ item: NewsItem) {
        preferences.hide(item)
        savePreferences()
        selectedItemID = visibleItems.first?.id
    }

    func suppressSimilar(to item: NewsItem) {
        preferences.suppressSimilar(to: item)
        savePreferences()
    }

    func blockSource(_ sourceID: String) {
        preferences.blockSource(sourceID)
        settings.enabledSourceIDs.remove(sourceID)
        savePreferences()
        saveSettings()
    }

    func setSource(_ option: NewsSourceOption, enabled: Bool) {
        if enabled {
            settings.enabledSourceIDs.formUnion(option.sourceIDs)
        } else {
            settings.enabledSourceIDs.subtract(option.sourceIDs)
        }
        saveSettings()
    }

    func updateSettings(_ update: (inout ViewerSettings) -> Void) {
        update(&settings)
        settings.normalize()
        saveSettings()
    }

    private func saveSettings() {
        syncStore.saveSettings(settings)
    }

    private func savePreferences() {
        syncStore.savePreferences(preferences)
    }

    private static func newestFirst(_ items: [NewsItem]) -> [NewsItem] {
        items.sorted { lhs, rhs in
            if lhs.publishedAt != rhs.publishedAt {
                return lhs.publishedAt > rhs.publishedAt
            }
            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }
            return lhs.id < rhs.id
        }
    }
}

struct NewsSourceOption: Identifiable, Equatable, Hashable {
    var id: String
    var displayName: String
    var sourceIDs: Set<String>

    init(id: String, displayName: String, sourceIDs: Set<String>? = nil) {
        self.id = id
        self.displayName = displayName
        self.sourceIDs = sourceIDs ?? [id]
    }

    static func grouped(from sources: [NewsSource]) -> [NewsSourceOption] {
        let groups = Dictionary(grouping: sources, by: \.displayName)

        return groups.map { displayName, sources in
            let sortedIDs = sources.map(\.id).sorted()
            let id = displayName == "MBC" ? "mbc" : sortedIDs.first ?? displayName
            return NewsSourceOption(
                id: id,
                displayName: displayName,
                sourceIDs: Set(sortedIDs)
            )
        }
        .sorted { lhs, rhs in
            lhs.displayName == rhs.displayName ? lhs.id < rhs.id : lhs.displayName < rhs.displayName
        }
    }

    func isEnabled(in enabledSourceIDs: Set<String>) -> Bool {
        !sourceIDs.isDisjoint(with: enabledSourceIDs)
    }
}
