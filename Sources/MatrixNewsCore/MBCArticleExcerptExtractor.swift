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
        let fullRange = NSRange(location: 0, length: (html as NSString).length)
        let matches = MBCExtractorRegex.openingDiv.matches(in: html, range: fullRange)

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
        let divTokens = MBCExtractorRegex.anyDivToken.matches(in: html, range: tokenRange)
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
        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        cleaned = MBCExtractorRegex.anyHTMLTag.stringByReplacingMatches(
            in: cleaned,
            options: [],
            range: range,
            withTemplate: " "
        )
        return cleaned.decodingHTMLEntities()
    }

    private static func isNoiseLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if MBCExtractorRegex.bracketLine.firstMatch(in: line, options: [], range: range) != nil {
            return true
        }
        if MBCExtractorRegex.chevronLine.firstMatch(in: line, options: [], range: range) != nil {
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

private enum MBCExtractorRegex {
    static let openingDiv: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"<div\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }()
    static let anyDivToken: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"</?div\b[^>]*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }()
    static let anyHTMLTag: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"<[^>]+>"#, options: [.caseInsensitive])
    }()
    static let whitespaceRun: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\s+"#)
    }()
    static let bracketLine: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\[[^\]]+\]$"#)
    }()
    static let chevronLine: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^◀\s*[^▶]+?\s*▶$"#)
    }()
    static let brTag: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"<\s*br\s*/?\s*>"#, options: [.caseInsensitive])
    }()
    static let closingP: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"</\s*p\s*>"#, options: [.caseInsensitive])
    }()
    static let closingDiv: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"</\s*div\s*>"#, options: [.caseInsensitive])
    }()
    static let hexEntity: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"&#x([0-9a-fA-F]+);"#)
    }()
    static let decimalEntity: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"&#([0-9]+);"#)
    }()
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
        let range = NSRange(startIndex..<endIndex, in: self)
        let collapsed = MBCExtractorRegex.whitespaceRun.stringByReplacingMatches(
            in: self,
            options: [],
            range: range,
            withTemplate: " "
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
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
        var result = self
        for regex in [MBCExtractorRegex.brTag, MBCExtractorRegex.closingP, MBCExtractorRegex.closingDiv] {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "\n"
            )
        }
        return result
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

        result = result.replacingNumericHTMLEntities(regex: MBCExtractorRegex.hexEntity, radix: 16)
        result = result.replacingNumericHTMLEntities(regex: MBCExtractorRegex.decimalEntity, radix: 10)
        return result
    }

    private func replacingNumericHTMLEntities(regex: NSRegularExpression, radix: Int) -> String {
        let nsString = self as NSString
        let matches = regex.matches(
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
