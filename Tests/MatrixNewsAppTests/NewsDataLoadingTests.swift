import Foundation
import Testing
@testable import MatrixNewsApp
@testable import MatrixNewsCore

@Suite("News data loading")
struct NewsDataLoadingTests {
    @Test("default remote base URL points at the public GitHub data folder")
    func defaultRemoteBaseURLPointsAtPublicGitHubDataFolder() {
        #expect(
            RemoteNewsDataLoader.defaultBaseURL.absoluteString
                == "https://raw.githubusercontent.com/pathcosmos/matrix-news-on-mac/main/Data/"
        )
    }

    @Test("explicit remote base URL values override the public GitHub default")
    func explicitRemoteBaseURLValuesOverridePublicGitHubDefault() {
        let infoPlistURL = RemoteNewsDataLoader.resolvedBaseURL(
            infoPlistValue: "https://example.com/info/",
            environmentValue: nil
        )
        let environmentURL = RemoteNewsDataLoader.resolvedBaseURL(
            infoPlistValue: "",
            environmentValue: "https://example.com/env/"
        )

        #expect(infoPlistURL.absoluteString == "https://example.com/info/")
        #expect(environmentURL.absoluteString == "https://example.com/env/")
    }

    @Test("remote loader follows manifest links and decodes latest news with sources")
    func remoteLoaderFollowsManifestLinks() async throws {
        let baseURL = URL(string: "https://raw.githubusercontent.com/example/matrix-news/main/Data/")!
        let generatedAt = Date(timeIntervalSince1970: 1_778_624_000)
        let latest = LatestNewsPayload(
            generatedAt: generatedAt,
            items: [
                NewsItem(
                    id: "remote-1",
                    title: "원격 뉴스",
                    sourceID: "mbc-politics",
                    sourceName: "MBC",
                    url: URL(string: "https://imnews.imbc.com/news/2026/politics/article/1.html")!,
                    publishedAt: generatedAt,
                    category: .politics,
                    keywords: ["원격", "뉴스"]
                )
            ]
        )
        let sources = [
            NewsSource(
                id: "mbc-politics",
                displayName: "MBC",
                feedURL: URL(string: "https://imnews.imbc.com/news/@@YEAR@@/politics/newest.js")!,
                homepageURL: URL(string: "https://imnews.imbc.com")!,
                defaultEnabled: true,
                licenseStatus: .testOnly,
                categories: [.politics]
            )
        ]
        let manifest = NewsFeedManifest(
            version: 1,
            generatedAt: generatedAt,
            latestURL: URL(string: "latest.json")!,
            sourcesURL: URL(string: "sources.json")!,
            itemCount: 1
        )
        let payloads = [
            baseURL.appendingPathComponent("manifest.json"): try JSONEncoder.matrixNews.encode(manifest),
            baseURL.appendingPathComponent("latest.json"): try JSONEncoder.matrixNews.encode(latest),
            baseURL.appendingPathComponent("sources.json"): try JSONEncoder.matrixNews.encode(sources)
        ]

        let loader = RemoteNewsDataLoader(baseURL: baseURL) { url in
            guard let data = payloads[url] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return data
        }

        let loaded = try await loader.load()

        #expect(loaded.latest == latest)
        #expect(loaded.sources == sources)
    }

    @Test("remote loader treats base URL without trailing slash as a directory")
    func remoteLoaderTreatsBaseURLWithoutTrailingSlashAsDirectory() async throws {
        let baseURL = URL(string: "https://raw.githubusercontent.com/example/matrix-news/main/Data")!
        let directoryURL = URL(string: "https://raw.githubusercontent.com/example/matrix-news/main/Data/")!
        let generatedAt = Date(timeIntervalSince1970: 1_778_624_000)
        let latest = LatestNewsPayload(generatedAt: generatedAt, items: [])
        let sources = [source(id: "mbc-headline", category: .politics)]
        let manifest = NewsFeedManifest(
            version: 1,
            generatedAt: generatedAt,
            latestURL: URL(string: "latest.json")!,
            sourcesURL: URL(string: "sources.json")!,
            itemCount: 0
        )
        let payloads = [
            directoryURL.appendingPathComponent("manifest.json"): try JSONEncoder.matrixNews.encode(manifest),
            directoryURL.appendingPathComponent("latest.json"): try JSONEncoder.matrixNews.encode(latest),
            directoryURL.appendingPathComponent("sources.json"): try JSONEncoder.matrixNews.encode(sources)
        ]

        let loader = RemoteNewsDataLoader(baseURL: baseURL) { url in
            guard let data = payloads[url] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return data
        }

        let loaded = try await loader.load()

        #expect(loaded.latest == latest)
        #expect(loaded.sources == sources)
    }

    @Test("MBC internal feeds are grouped into one source option")
    func mbcInternalFeedsAreGroupedIntoOneSourceOption() {
        let sources = [
            source(id: "mbc-politics", category: .politics),
            source(id: "mbc-society", category: .society),
            source(id: "mbc-sports", category: .sports)
        ]

        let options = NewsSourceOption.grouped(from: sources)

        #expect(options.map { [$0.id, $0.displayName] } == [["mbc", "MBC"]])
        #expect(options[0].sourceIDs == ["mbc-politics", "mbc-society", "mbc-sports"])
    }

    @Test("news data loader falls back to bundled data when remote loading fails")
    func newsDataLoaderFallsBackToBundledDataWhenRemoteLoadingFails() async {
        let bundled = NewsDataPayload(
            latest: LatestNewsPayload(generatedAt: Date(timeIntervalSince1970: 2), items: []),
            sources: [source(id: "mbc-politics", category: .politics)]
        )
        let fallback = NewsDataPayload(
            latest: LatestNewsPayload(generatedAt: Date(timeIntervalSince1970: 1), items: []),
            sources: []
        )
        let loader = NewsDataLoader(
            remoteLoad: {
                throw CocoaError(.fileReadUnknown)
            },
            bundledLoad: {
                bundled
            },
            fallback: fallback
        )

        let loaded = await loader.load()

        #expect(loaded == bundled)
    }

    @Test("bundled generated latest feed contains fifty items")
    func bundledGeneratedLatestFeedContainsFiftyItems() throws {
        let latest = try BundleJSONLoader.decode(LatestNewsPayload.self, resource: "latest")
        let sources = try BundleJSONLoader.decode([NewsSource].self, resource: "sources")

        #expect(latest.items.count == 50)
        #expect(Set(latest.items.map(\.url)).count == 50)
        #expect(latest.items.allSatisfy { item in
            let summary = item.summary ?? ""
            return !summary.contains("mbcjebo@mbc.co.kr")
                && !summary.contains("02-784-4000")
                && !summary.contains("MBC 뉴스는 24시간 여러분의 제보를 기다립니다")
        })
        #expect(sources.map(\.displayName).allSatisfy { $0 == "MBC" })
    }

    @Test("public data latest feed contains fifty clean summaries")
    func publicDataLatestFeedContainsFiftyCleanSummaries() throws {
        let latestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Data/latest.json")
        let latest = try JSONDecoder.matrixNews.decode(
            LatestNewsPayload.self,
            from: Data(contentsOf: latestURL)
        )

        #expect(latest.items.count == 50)
        #expect(Set(latest.items.map(\.url)).count == 50)
        #expect(latest.items.allSatisfy { item in
            let summary = item.summary ?? ""
            return !summary.hasPrefix("https://")
                && !summary.contains("mbcjebo@mbc.co.kr")
                && !summary.contains("02-784-4000")
                && !summary.contains("MBC 뉴스는 24시간 여러분의 제보를 기다립니다")
        })
    }

    private func source(id: String, category: NewsCategory) -> NewsSource {
        NewsSource(
            id: id,
            displayName: "MBC",
            feedURL: URL(string: "https://imnews.imbc.com/news/@@YEAR@@/\(id)/newest.js")!,
            homepageURL: URL(string: "https://imnews.imbc.com")!,
            defaultEnabled: true,
            licenseStatus: .testOnly,
            categories: [category]
        )
    }
}
