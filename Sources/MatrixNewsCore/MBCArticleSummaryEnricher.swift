import Foundation

public struct MBCArticleSummaryEnricher: Sendable {
    public typealias FetchHTML = @Sendable (URL) async throws -> String

    private var extractor: MBCArticleExcerptExtractor
    private var maxConcurrentRequests: Int
    private var fetchHTML: FetchHTML

    public init(
        extractor: MBCArticleExcerptExtractor = MBCArticleExcerptExtractor(),
        maxConcurrentRequests: Int = 4,
        fetchHTML: @escaping FetchHTML
    ) {
        self.extractor = extractor
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
        self.fetchHTML = fetchHTML
    }

    public func enrich(_ items: [NewsItem]) async -> [NewsItem] {
        let candidateIndices = items.indices.filter { Self.shouldEnrich(items[$0]) }
        guard !candidateIndices.isEmpty else { return items }

        var enrichedItems = items
        var batchStart = 0

        while batchStart < candidateIndices.count {
            let batchEnd = min(batchStart + maxConcurrentRequests, candidateIndices.count)
            let batch = Array(candidateIndices[batchStart..<batchEnd])
            let results = await fetchExcerpts(for: batch, in: items)

            for (index, excerpt) in results where excerpt?.isEmpty == false {
                enrichedItems[index].summary = excerpt
            }

            batchStart = batchEnd
        }

        return enrichedItems
    }

    public static func shouldEnrich(_ item: NewsItem) -> Bool {
        guard isSupportedArticleURL(item.url) else { return false }

        let summary = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return summary.isEmpty || summary.hasPrefix("https://imnews.imbc.com/")
    }

    public static func isSupportedArticleURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "imnews.imbc.com" else {
            return false
        }

        let path = url.path.lowercased()
        return path.contains("/article/") && path.hasSuffix(".html")
    }

    private func fetchExcerpts(
        for indices: [Array<NewsItem>.Index],
        in items: [NewsItem]
    ) async -> [(Array<NewsItem>.Index, String?)] {
        await withTaskGroup(of: (Array<NewsItem>.Index, String?).self) { group in
            for index in indices {
                let url = items[index].url
                let extractor = extractor
                let fetchHTML = fetchHTML

                group.addTask {
                    do {
                        let html = try await fetchHTML(url)
                        return (index, extractor.extract(fromHTML: html))
                    } catch {
                        return (index, nil)
                    }
                }
            }

            var results: [(Array<NewsItem>.Index, String?)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
}
