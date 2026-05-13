import Foundation
import MatrixNewsCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct MatrixNewsFetcher {
    static func main() async throws {
        let arguments = FetcherArguments(CommandLine.arguments.dropFirst())
        let sourcesData = try Data(contentsOf: arguments.sourcesURL)
        let allSources = try JSONDecoder.matrixNews.decode([NewsSource].self, from: sourcesData)
        let eligibleSources = allSources.filter { source in
            source.defaultEnabled && arguments.licenseScope.allows(source.licenseStatus)
        }
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())

        var fetchedItems: [NewsItem] = []
        for source in eligibleSources {
            do {
                let (data, _) = try await URLSession.shared.data(
                    from: source.resolvedFeedURL(currentYear: currentYear)
                )
                let items = try parse(data, source: source)
                fetchedItems.append(contentsOf: items)
                FileHandle.standardError.writeLine("Fetched \(items.count) items from \(source.displayName)")
            } catch {
                FileHandle.standardError.writeLine("Failed \(source.displayName): \(error)")
            }
        }

        let deduplicatedItems = Array(NewsDeduplicator.deduplicate(fetchedItems).prefix(arguments.limit))
        let outputItems = await enrichMBCSummaries(in: deduplicatedItems)
        guard outputItems.count >= arguments.minimumItems else {
            throw FetcherError.insufficientItems(
                expected: arguments.minimumItems,
                actual: outputItems.count
            )
        }

        let generatedAt = Date()
        let latestPayload = LatestNewsPayload(generatedAt: generatedAt, items: outputItems)
        let manifest = NewsFeedManifest(
            version: 1,
            generatedAt: generatedAt,
            latestURL: URL(string: "latest.json")!,
            sourcesURL: URL(string: "sources.json")!,
            itemCount: outputItems.count
        )

        try FileManager.default.createDirectory(
            at: arguments.outputURL,
            withIntermediateDirectories: true
        )

        try JSONEncoder.matrixNews.encode(latestPayload).writeAtomically(
            to: arguments.outputURL.appendingPathComponent("latest.json")
        )
        try JSONEncoder.matrixNews.encode(eligibleSources).writeAtomically(
            to: arguments.outputURL.appendingPathComponent("sources.json")
        )
        try JSONEncoder.matrixNews.encode(manifest).writeAtomically(
            to: arguments.outputURL.appendingPathComponent("manifest.json")
        )

        FileHandle.standardError.writeLine("Wrote \(outputItems.count) items to \(arguments.outputURL.path)")
    }

    private static func enrichMBCSummaries(in items: [NewsItem]) async -> [NewsItem] {
        let candidates = items.filter(MBCArticleSummaryEnricher.shouldEnrich)
        guard !candidates.isEmpty else { return items }

        let enricher = MBCArticleSummaryEnricher(fetchHTML: { url in
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            request.setValue(
                "MatrixNewsFetcher/1.0 (+https://imnews.imbc.com)",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(decoding: data, as: UTF8.self)
        })
        let enriched = await enricher.enrich(items)
        let enrichedCount = zip(items, enriched).filter { $0.summary != $1.summary }.count
        FileHandle.standardError.writeLine(
            "Enriched \(enrichedCount)/\(candidates.count) MBC article summaries"
        )
        return enriched
    }

    private static func parse(_ data: Data, source: NewsSource) throws -> [NewsItem] {
        if source.feedURL.pathExtension == "js" && source.feedURL.host?.contains("imbc.com") == true {
            return try MBCNewsJSONFeedParser().parse(data, source: source)
        }

        return try RSSFeedParser().parse(data, source: source)
    }
}

private struct FetcherArguments {
    var sourcesURL = URL(fileURLWithPath: "Config/news-sources.json")
    var outputURL = URL(fileURLWithPath: "Data")
    var licenseScope = LicenseScope.testOnly
    var limit = 50
    var minimumItems = 1

    init(_ rawArguments: ArraySlice<String>) {
        var iterator = rawArguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--sources":
                if let value = iterator.next() {
                    sourcesURL = URL(fileURLWithPath: value)
                }
            case "--output":
                if let value = iterator.next() {
                    outputURL = URL(fileURLWithPath: value)
                }
            case "--license-scope":
                if let value = iterator.next(), let scope = LicenseScope(rawValue: value) {
                    licenseScope = scope
                }
            case "--limit":
                if let value = iterator.next(), let parsed = Int(value) {
                    limit = parsed
                }
            case "--minimum-items":
                if let value = iterator.next(), let parsed = Int(value) {
                    minimumItems = parsed
                }
            default:
                break
            }
        }
    }
}

private enum FetcherError: Error, CustomStringConvertible {
    case insufficientItems(expected: Int, actual: Int)

    var description: String {
        switch self {
        case let .insufficientItems(expected, actual):
            return "Fetched \(actual) unique items, expected at least \(expected); keeping existing news data."
        }
    }
}

private enum LicenseScope: String {
    case licensed
    case testOnly = "test-only"
    case all

    func allows(_ status: LicenseStatus) -> Bool {
        switch self {
        case .licensed:
            return status == .licensed
        case .testOnly:
            return status == .licensed || status == .testOnly
        case .all:
            return true
        }
    }
}

private extension Data {
    func writeAtomically(to url: URL) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".tmp")
        try write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: url)
    }
}

private extension FileHandle {
    func writeLine(_ value: String) {
        if let data = (value + "\n").data(using: .utf8) {
            write(data)
        }
    }
}
