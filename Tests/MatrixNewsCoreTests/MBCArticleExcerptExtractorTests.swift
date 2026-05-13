import Foundation
import Testing
@testable import MatrixNewsCore

@Suite("MBC article excerpt extractor")
struct MBCArticleExcerptExtractorTests {
    @Test("extracts article body text while removing page chrome noise")
    func extractsArticleBodyText() {
        let html = """
        <!doctype html>
        <html>
          <body>
            <div class="unrelated">메뉴 텍스트</div>
            <div class="news_txt" itemprop="articleBody">
              <figure>
                <img src="/photo.jpg">
                <figcaption>사진 설명은 본문이 아닙니다.</figcaption>
              </figure>
              [뉴스데스크]<br>
              ◀ 앵커 ▶<br>
              첫 번째 문장입니다.<br><br>
              두 번째 문장에는 &amp; 기호가 들어갑니다.<br>
              <a href="https://imnews.imbc.com/replay/2026/nwdesk/article/1.html">관련 보도</a><br>
              https://imnews.imbc.com/replay/2026/nwdesk/article/1.html<br>
              #해시태그 #MBC뉴스<br>
              제보는 카카오톡 @mbc제보로 보내주세요.
            </div>
          </body>
        </html>
        """

        let excerpt = MBCArticleExcerptExtractor().extract(fromHTML: html)

        #expect(excerpt == "첫 번째 문장입니다. 두 번째 문장에는 & 기호가 들어갑니다.")
    }

    @Test("extracts replay article body without video wrapper text")
    func extractsReplayArticleBodyWithoutVideoWrapperText() {
        let html = """
        <html>
          <body>
            <div class="news_txt" itemprop="articleBody">
              <div class="vod_player">
                <button>재생</button>
                <span>동영상 영역</span>
              </div>
              ◀ 리포트 ▶<br>
              다시보기 기사 첫 문장입니다.<br>
              이어지는 본문입니다.
            </div>
          </body>
        </html>
        """

        let excerpt = MBCArticleExcerptExtractor().extract(fromHTML: html)

        #expect(excerpt == "다시보기 기사 첫 문장입니다. 이어지는 본문입니다.")
    }

    @Test("truncates near the character limit at a sentence boundary")
    func truncatesAtSentenceBoundary() {
        let first = String(repeating: "가", count: 120) + "."
        let second = String(repeating: "나", count: 120) + "."
        let third = String(repeating: "다", count: 120) + "."
        let html = """
        <div class="news_txt" itemprop="articleBody">
          \(first) \(second) \(third)
        </div>
        """

        let excerpt = MBCArticleExcerptExtractor(maxCharacters: 300).extract(fromHTML: html)

        #expect(excerpt == "\(first) \(second)")
        #expect((excerpt?.count ?? 0) <= 300)
    }

    @Test("removes MBC report footer from article excerpts")
    func removesMBCReportFooterFromArticleExcerpts() {
        let html = """
        <div class="news_txt" itemprop="articleBody">
          기사 본문 첫 문장입니다.<br>
          이어지는 핵심 문장입니다.<br>
          MBC 뉴스는 24시간 여러분의 제보를 기다립니다.<br>
          ▷ 전화 02-784-4000<br>
          ▷ 이메일 mbcjebo@mbc.co.kr
        </div>
        """

        let excerpt = MBCArticleExcerptExtractor().extract(fromHTML: html)

        #expect(excerpt == "기사 본문 첫 문장입니다. 이어지는 핵심 문장입니다.")
    }
}
