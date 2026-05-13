import Foundation

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

enum BundleJSONLoader {
    static func decode<T: Decodable>(_ type: T.Type, resource: String) throws -> T {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.matrixNews.decode(T.self, from: data)
    }
}

struct NewsDataPayload: Equatable, Sendable {
    var latest: LatestNewsPayload
    var sources: [NewsSource]
}

struct RemoteNewsDataLoader: Sendable {
    typealias Fetch = @Sendable (URL) async throws -> Data

    static let defaultBaseURL = URL(
        string: "https://raw.githubusercontent.com/pathcosmos/matrix-news-on-mac/main/Data/"
    )!

    var baseURL: URL
    var fetch: Fetch

    init(
        baseURL: URL,
        fetch: @escaping Fetch = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
    ) {
        self.baseURL = baseURL.directoryURL
        self.fetch = fetch
    }

    func load() async throws -> NewsDataPayload {
        let manifestData = try await fetch(resolve(URL(string: "manifest.json")!))
        let manifest = try JSONDecoder.matrixNews.decode(NewsFeedManifest.self, from: manifestData)
        let latestData = try await fetch(resolve(manifest.latestURL))
        let sourcesData = try await fetch(resolve(manifest.sourcesURL))

        return NewsDataPayload(
            latest: try JSONDecoder.matrixNews.decode(LatestNewsPayload.self, from: latestData),
            sources: try JSONDecoder.matrixNews.decode([NewsSource].self, from: sourcesData)
        )
    }

    private func resolve(_ url: URL) -> URL {
        if url.scheme != nil {
            return url
        }
        return URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL
            ?? baseURL.appendingPathComponent(url.relativeString)
    }

    static var configuredBaseURL: URL? {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "NEWS_DATA_BASE_URL") as? String
        let environmentValue = ProcessInfo.processInfo.environment["NEWS_DATA_BASE_URL"]
        return configuredBaseURL(
            infoPlistValue: bundleValue,
            environmentValue: environmentValue
        )
    }

    static func configuredBaseURL(
        infoPlistValue: String?,
        environmentValue: String?
    ) -> URL? {
        let value = (infoPlistValue?.isEmpty == false ? infoPlistValue : environmentValue) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(string: trimmed)
    }

    static var resolvedBaseURL: URL {
        resolvedBaseURL(
            infoPlistValue: Bundle.main.object(forInfoDictionaryKey: "NEWS_DATA_BASE_URL") as? String,
            environmentValue: ProcessInfo.processInfo.environment["NEWS_DATA_BASE_URL"]
        )
    }

    static func resolvedBaseURL(
        infoPlistValue: String?,
        environmentValue: String?
    ) -> URL {
        configuredBaseURL(
            infoPlistValue: infoPlistValue,
            environmentValue: environmentValue
        ) ?? defaultBaseURL
    }
}

private extension URL {
    var directoryURL: URL {
        if absoluteString.hasSuffix("/") {
            return self
        }
        return URL(string: absoluteString + "/") ?? self
    }
}

struct NewsDataLoader: Sendable {
    typealias RemoteLoad = @Sendable () async throws -> NewsDataPayload
    typealias BundledLoad = @Sendable () throws -> NewsDataPayload

    var remoteLoad: RemoteLoad?
    var bundledLoad: BundledLoad
    var fallback: NewsDataPayload

    func load() async -> NewsDataPayload {
        if let remoteLoad, let remotePayload = try? await remoteLoad() {
            return remotePayload
        }

        if let bundledPayload = try? bundledLoad() {
            return bundledPayload
        }

        return fallback
    }

    func loadRemote() async -> NewsDataPayload? {
        guard let remoteLoad else { return nil }
        return try? await remoteLoad()
    }

    static func appDefault() -> NewsDataLoader {
        let fallback = NewsDataPayload(
            latest: LatestNewsPayload(generatedAt: Date(), items: SampleNews.items),
            sources: SampleNews.newsSources
        )
        let remoteLoad: RemoteLoad = {
            try await RemoteNewsDataLoader(
                baseURL: RemoteNewsDataLoader.resolvedBaseURL
            ).load()
        }

        return NewsDataLoader(
            remoteLoad: remoteLoad,
            bundledLoad: {
                if let generated = try? bundledPayload(latestResource: "latest", sourcesResource: "sources") {
                    return generated
                }

                return try bundledPayload(
                    latestResource: "latest.sample",
                    sourcesResource: "sources.sample"
                )
            },
            fallback: fallback
        )
    }

    private static func bundledPayload(
        latestResource: String,
        sourcesResource: String
    ) throws -> NewsDataPayload {
        NewsDataPayload(
            latest: try BundleJSONLoader.decode(
                LatestNewsPayload.self,
                resource: latestResource
            ),
            sources: try BundleJSONLoader.decode(
                [NewsSource].self,
                resource: sourcesResource
            )
        )
    }
}
