import Foundation

public enum KeywordExtractor {
    private static let stopwords: Set<String> = [
        "그리고", "그러나", "대한", "관련", "기자", "뉴스", "단독", "속보", "오늘",
        "내일", "이번", "지난", "최근", "현장", "종합", "영상", "사진", "the",
        "and", "for", "with", "from", "this", "that"
    ]

    public static func keywords(from text: String, limit: Int = 8) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            let token = current.lowercased()
            if token.count > 1, !stopwords.contains(token), !tokens.contains(token) {
                tokens.append(token)
            }
            current = ""
        }

        for scalar in text.unicodeScalars {
            if scalar.isMatrixNewsTokenScalar {
                current.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()

        return Array(tokens.prefix(limit))
    }
}

private extension Unicode.Scalar {
    var isMatrixNewsTokenScalar: Bool {
        CharacterSet.alphanumerics.contains(self)
            || (0xAC00...0xD7A3).contains(value)
    }
}
