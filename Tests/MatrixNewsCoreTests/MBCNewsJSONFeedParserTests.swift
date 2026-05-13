import Foundation
import Testing
@testable import MatrixNewsCore

@Suite("MBC news JSON feed parser")
struct MBCNewsJSONFeedParserTests {
    @Test("parses MBC headline data into news items")
    func parsesMBCHeadlineData() throws {
        let json = """
        {
          "Data": [
            {
              "Section": "정치",
              "AId": "6822061",
              "Title": "김민석 총리 \\"삼성전자, 어떠한 경우에도 파업으로 이어지지 않도록\\"",
              "Desc": "삼성전자의 노사 협상이 결렬된 가운데 김민석 국무총리가 상황이 파업으로 이어지지 않도록 노사 대화를 지원하라고 당부했습니다.",
              "Link": "https://imnews.imbc.com/news/2026/politics/article/6822061_36911.html",
              "IsVod": "N"
            }
          ]
        }
        """
        let source = NewsSource(
            id: "mbc-headline",
            displayName: "MBC",
            feedURL: URL(string: "https://imnews.imbc.com/operate/common/main/topnews/headline_news.js")!,
            homepageURL: URL(string: "https://imnews.imbc.com")!,
            defaultEnabled: true,
            licenseStatus: .testOnly,
            categories: [.politics, .economy, .society]
        )

        let items = try MBCNewsJSONFeedParser(
            currentDate: Date(timeIntervalSince1970: 1_778_624_000)
        )
        .parse(Data(json.utf8), source: source)

        #expect(items.count == 1)
        #expect(items[0].id == "mbc-headline-6822061")
        #expect(items[0].sourceID == "mbc-headline")
        #expect(items[0].sourceName == "MBC")
        #expect(items[0].category == .politics)
        #expect(items[0].summary == "삼성전자의 노사 협상이 결렬된 가운데 김민석 국무총리가 상황이 파업으로 이어지지 않도록 노사 대화를 지원하라고 당부했습니다.")
        #expect(items[0].publishedAt == Date(timeIntervalSince1970: 1_778_624_000))
    }

    @Test("parses MBC category newest data with optional description")
    func parsesMBCCategoryNewestData() throws {
        let json = """
        {
          "Data": [
            {
              "Section": "경제",
              "AId": "6822092",
              "Title": "오늘의 증시",
              "Link": "https://imnews.imbc.com/replay/2026/nw1200/article/6822092_36967.html",
              "StartDate": "2026-05-13",
              "Author": "정다인/삼성증권"
            }
          ]
        }
        """
        let source = NewsSource(
            id: "mbc-economy",
            displayName: "MBC",
            feedURL: URL(string: "https://imnews.imbc.com/news/@@YEAR@@/econo/newest.js")!,
            homepageURL: URL(string: "https://imnews.imbc.com")!,
            defaultEnabled: true,
            licenseStatus: .testOnly,
            categories: [.economy]
        )

        let items = try MBCNewsJSONFeedParser(
            currentDate: Date(timeIntervalSince1970: 1_778_624_000)
        )
        .parse(Data(json.utf8), source: source)

        #expect(items.count == 1)
        #expect(items[0].id == "mbc-economy-6822092")
        #expect(items[0].category == .economy)
        #expect(items[0].summary == nil)
        #expect(items[0].publishedAt == ISO8601DateFormatter().date(from: "2026-05-13T00:00:00Z"))
    }

    @Test("strips MBC report footer from JSON descriptions")
    func stripsMBCReportFooterFromJSONDescriptions() throws {
        let json = """
        {
          "Data": [
            {
              "Section": "정치",
              "AId": "6823000",
              "Title": "제보 안내 제거 테스트",
              "Desc": "본문 요약입니다. MBC 뉴스는 24시간 여러분의 제보를 기다립니다. ▷ 전화 02-784-4000 ▷ 이메일 mbcjebo@mbc.co.kr",
              "Link": "https://imnews.imbc.com/news/2026/politics/article/6823000_36911.html"
            }
          ]
        }
        """
        let source = NewsSource(
            id: "mbc-politics",
            displayName: "MBC",
            feedURL: URL(string: "https://imnews.imbc.com/news/@@YEAR@@/politics/newest.js")!,
            homepageURL: URL(string: "https://imnews.imbc.com")!,
            defaultEnabled: true,
            licenseStatus: .testOnly,
            categories: [.politics]
        )

        let items = try MBCNewsJSONFeedParser()
            .parse(Data(json.utf8), source: source)

        #expect(items[0].summary == "본문 요약입니다.")
    }

    @Test("falls back when optional MBC fields are missing")
    func fallsBackWhenOptionalMBCFieldsAreMissing() throws {
        let json = """
        {
          "Data": [
            {
              "Title": "스포츠 속보",
              "Link": "https://imnews.imbc.com/news/2026/sports/article/6822000_36940.html"
            }
          ]
        }
        """
        let source = NewsSource(
            id: "mbc-sports",
            displayName: "MBC",
            feedURL: URL(string: "https://imnews.imbc.com/news/@@YEAR@@/sports/newest.js")!,
            homepageURL: URL(string: "https://imnews.imbc.com")!,
            defaultEnabled: true,
            licenseStatus: .testOnly,
            categories: [.sports]
        )
        let currentDate = Date(timeIntervalSince1970: 1_778_624_000)
        let url = URL(string: "https://imnews.imbc.com/news/2026/sports/article/6822000_36940.html")!

        let items = try MBCNewsJSONFeedParser(currentDate: currentDate)
            .parse(Data(json.utf8), source: source)

        #expect(items.count == 1)
        #expect(items[0].id == NewsItem.makeID(sourceID: "mbc-sports", url: url, title: "스포츠 속보"))
        #expect(items[0].category == .sports)
        #expect(items[0].summary == nil)
        #expect(items[0].publishedAt == currentDate)
    }

    @Test("date-only MBC newest entries retain fetch order")
    func dateOnlyMBCNewestEntriesRetainFetchOrder() throws {
        let json = """
        {
          "Data": [
            {
              "Section": "문화",
              "AId": "1",
              "Title": "첫 번째 문화 기사",
              "Link": "https://imnews.imbc.com/news/2026/culture/article/1.html",
              "StartDate": "2026-05-13"
            },
            {
              "Section": "문화",
              "AId": "2",
              "Title": "두 번째 문화 기사",
              "Link": "https://imnews.imbc.com/news/2026/culture/article/2.html",
              "StartDate": "2026-05-13"
            }
          ]
        }
        """
        let source = NewsSource(
            id: "mbc-culture",
            displayName: "MBC",
            feedURL: URL(string: "https://imnews.imbc.com/news/@@YEAR@@/culture/newest.js")!,
            homepageURL: URL(string: "https://imnews.imbc.com")!,
            defaultEnabled: true,
            licenseStatus: .testOnly,
            categories: [.culture]
        )

        let items = try MBCNewsJSONFeedParser()
            .parse(Data(json.utf8), source: source)

        #expect(items[0].publishedAt > items[1].publishedAt)
    }
}
