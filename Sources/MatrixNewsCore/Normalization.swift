import Foundation

public enum URLNormalizer {
    private static let removableQueryNames: Set<String> = [
        "fbclid", "gclid", "igshid", "mc_cid", "mc_eid", "ncid", "ref", "spm"
    ]

    public static func normalizedURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        if let items = components.queryItems {
            let filtered = items
                .filter { item in
                    let name = item.name.lowercased()
                    return !name.hasPrefix("utm_") && !removableQueryNames.contains(name)
                }
                .sorted { lhs, rhs in
                    lhs.name == rhs.name
                        ? (lhs.value ?? "") < (rhs.value ?? "")
                        : lhs.name < rhs.name
                }

            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        if components.path != "/", components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        return components.url ?? url
    }

    public static func normalizedURLString(_ url: URL) -> String {
        normalizedURL(url).absoluteString
    }
}

public extension String {
    var normalizedForMatching: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

public enum StableHash {
    public static func hexDigest(_ input: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
