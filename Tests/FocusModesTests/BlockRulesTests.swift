import Testing
@testable import FocusModes

// Real blocks, imported from Cold Turkey.
@Suite struct BlockRulesTests {
    let work = BlockRule(apps: ["com.tdesktop.telegram"], web: ["google.com"],
                         exceptions: ["accounts.google.com", "github.com", "localhost:3000", "mail.google.com",
                                      "meet.google.com/home", "file://*.*", "youtube.com"])
    let interview = BlockRule(web: ["*"], exceptions: ["accounts.google.com", "bigfrontend.dev"])
    let insta = BlockRule(web: ["instagram.com", "xhamster.*"], exceptions: ["instagram.com/p/*"])

    @Test func domainWithSubdomainsAndExceptions() {
        #expect(work.blocks(url: "https://www.google.com/search?q=x"))
        #expect(work.blocks(url: "https://google.com"))
        #expect(work.blocks(url: "https://news.google.com/"))
        #expect(!work.blocks(url: "https://mail.google.com/mail/u/0/"))
        #expect(!work.blocks(url: "https://meet.google.com/home"))
        #expect(!work.blocks(url: "https://github.com/x/y"))
        #expect(!work.blocks(url: "http://localhost:3000/app"))
    }

    @Test func lookalikesAreNotMatched() {
        #expect(!work.blocks(url: "https://notgoogle.com/"))
        #expect(!work.blocks(url: "https://google.com.evil.io/"))
    }

    @Test func browserPagesAreNeverBlocked() {
        #expect(!work.blocks(url: "file:///Users/me/a.html"))
        #expect(!work.blocks(url: "chrome://settings"))
        #expect(!interview.blocks(url: "chrome://newtab/"))
        #expect(!interview.blocks(url: "about:blank"))
    }

    @Test func everythingButExceptions() {
        #expect(interview.blocks(url: "https://x.com/home"))
        #expect(interview.blocks(url: "file:///Users/me/a.html"))
        #expect(!interview.blocks(url: "https://bigfrontend.dev/problem/1"))
        #expect(!interview.blocks(url: "https://accounts.google.com/signin"))
    }

    @Test func pathAndTldWildcards() {
        #expect(insta.blocks(url: "https://www.instagram.com/"))
        #expect(insta.blocks(url: "https://www.instagram.com/reels/"))
        #expect(!insta.blocks(url: "https://www.instagram.com/p/abc/"))
        #expect(insta.blocks(url: "https://xhamster.desi/videos"))
    }

    @Test func lockedRulesOnlyGetStricter() {
        let edited = BlockRule(apps: ["com.apple.Music"], web: ["x.com"], exceptions: ["github.com", "reddit.com"])
        let r = work.stricter(edited)
        #expect(r.apps == ["com.tdesktop.telegram", "com.apple.Music"])
        #expect(r.web == ["google.com", "x.com"])
        #expect(r.exceptions == ["github.com"])
    }
}
