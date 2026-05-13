import Foundation

public struct MBCArticleExcerptExtractor: Sendable {
    public var maxCharacters: Int

    public init(maxCharacters: Int = 300) {
        self.maxCharacters = max(1, maxCharacters)
    }

    public func extract(fromHTML html: String) -> String? {
        guard let bodyHTML = Self.articleBodyHTML(from: html) else {
            return nil
        }

        let text = Self.textContent(from: bodyHTML)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.collapsedWhitespace }
            .filter { !$0.isEmpty }
            .filter { !Self.isNoiseLine($0) }

        let normalized = lines.joined(separator: " ").collapsedWhitespace
        guard let cleaned = SummaryCleaner.clean(normalized) else { return nil }

        return Self.truncate(cleaned, maxCharacters: maxCharacters)
    }

    private static func articleBodyHTML(from html: String) -> String? {
        let openingDivPattern = #"<div\b([^>]*)>"#
        let matches = html.matches(
            pattern: openingDivPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        for match in matches {
            let attributes = html.substring(match.range(at: 1)).lowercased()
            guard attributes.contains("news_txt") || attributes.contains("articlebody") else {
                continue
            }

            let start = match.range.upperBound
            guard let end = matchingDivEnd(in: html, after: start) else {
                continue
            }
            return html.substring(NSRange(location: start, length: end - start))
        }

        return nil
    }

    private static func matchingDivEnd(in html: String, after start: Int) -> Int? {
        let remainingLength = (html as NSString).length - start
        guard remainingLength > 0 else { return nil }

        let tokenRange = NSRange(location: start, length: remainingLength)
        let divTokens = html.matches(
            pattern: #"</?div\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators],
            range: tokenRange
        )
        var depth = 1

        for token in divTokens {
            let value = html.substring(token.range).lowercased()
            if value.hasPrefix("</div") {
                depth -= 1
                if depth == 0 {
                    return token.range.location
                }
            } else {
                depth += 1
            }
        }

        return nil
    }

    private static func textContent(from html: String) -> String {
        var cleaned = html
        cleaned = cleaned.removingHTMLBlocks(named: [
            "script", "style", "noscript", "figure", "figcaption",
            "picture", "iframe", "video", "audio"
        ])
        cleaned = cleaned.removingDivBlocks(containingAttributeTokens: [
            "vod", "video", "player", "share", "sns", "relat", "tag"
        ])
        cleaned = cleaned.replacingHTMLLineBreaks()
        cleaned = cleaned.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        return cleaned.decodingHTMLEntities()
    }

    private static func isNoiseLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        if line.range(of: #"^\[[^\]]+\]$"#, options: .regularExpression) != nil {
            return true
        }
        if line.range(of: #"^◀\s*[^▶]+?\s*▶$"#, options: .regularExpression) != nil {
            return true
        }
        if lowercased.hasPrefix("https://imnews.imbc.com/") {
            return true
        }
        if line.hasPrefix("#") {
            return true
        }
        if line.contains("관련 보도") || line.contains("관련기사") {
            return true
        }
        if line.contains("제보는") || line.contains("제보하기") || line.contains("@mbc제보") {
            return true
        }
        if line.contains("MBC 뉴스는 24시간 여러분의 제보를 기다립니다")
            || line.contains("02-784-4000")
            || line.contains("mbcjebo@mbc.co.kr") {
            return true
        }
        return false
    }

    private static func truncate(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }

        let prefix = String(text.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceEnders: Set<Character> = [".", "?", "!", "。", "…"]
        var bestBoundary: String.Index?

        for index in prefix.indices where sentenceEnders.contains(prefix[index]) {
            let next = prefix.index(after: index)
            if next == prefix.endIndex || prefix[next].isWhitespace {
                bestBoundary = next
            }
        }

        if let bestBoundary {
            let truncated = String(prefix[..<bestBoundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !truncated.isEmpty {
                return truncated
            }
        }

        return prefix
    }
}

private extension String {
    func matches(
        pattern: String,
        options: NSRegularExpression.Options = [],
        range: NSRange? = nil
    ) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let fullRange = NSRange(location: 0, length: (self as NSString).length)
        return expression.matches(in: self, range: range ?? fullRange)
    }

    func substring(_ range: NSRange) -> String {
        (self as NSString).substring(with: range)
    }

    var collapsedWhitespace: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removingHTMLBlocks(named names: [String]) -> String {
        names.reduce(self) { result, name in
            result.replacingOccurrences(
                of: #"(?is)<\#(name)\b[^>]*>.*?</\#(name)>"#,
                with: " ",
                options: .regularExpression
            )
        }
    }

    func removingDivBlocks(containingAttributeTokens tokens: [String]) -> String {
        var result = self
        for token in tokens {
            result = result.replacingOccurrences(
                of: #"(?is)<div\b[^>]*\#(token)[^>]*>.*?</div>"#,
                with: " ",
                options: .regularExpression
            )
        }
        return result
    }

    func replacingHTMLLineBreaks() -> String {
        replacingOccurrences(
            of: #"(?i)<\s*br\s*/?\s*>"#,
            with: "\n",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"(?i)</\s*p\s*>"#,
            with: "\n",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"(?i)</\s*div\s*>"#,
            with: "\n",
            options: .regularExpression
        )
    }

    func decodingHTMLEntities() -> String {
        var result = self
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        result = result.replacingNumericHTMLEntities(pattern: #"&#x([0-9a-fA-F]+);"#, radix: 16)
        result = result.replacingNumericHTMLEntities(pattern: #"&#([0-9]+);"#, radix: 10)
        return result
    }

    private func replacingNumericHTMLEntities(pattern: String, radix: Int) -> String {
        let nsString = self as NSString
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return self }
        let matches = expression.matches(
            in: self,
            range: NSRange(location: 0, length: nsString.length)
        )
        var result = self

        for match in matches.reversed() {
            let value = nsString.substring(with: match.range(at: 1))
            guard let scalarValue = UInt32(value, radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            let range = Range(match.range, in: result)!
            result.replaceSubrange(range, with: String(Character(scalar)))
        }

        return result
    }
}
