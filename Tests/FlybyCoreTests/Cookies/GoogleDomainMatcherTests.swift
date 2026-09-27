import Testing
@testable import FlybyCore

@Suite struct GoogleDomainMatcherTests {
    @Test(arguments: [
        "google.com",
        ".google.com",
        "www.google.com",
        "accounts.google.com",
        "mail.google.com",
        "GOOGLE.COM",              // case-insensitive
        "google.de",
        ".google.de",
        "google.co.uk",
        "www.google.co.uk",
        "google.com.au",
        "www.google.com.au",
        "google.co",               // Colombia
        "google.com.",             // trailing dot (FQDN)
    ])
    func matchesGoogleDomains(_ domain: String) {
        #expect(GoogleDomainMatcher.matches(domain), "expected \(domain) to match")
        #expect(GoogleCookies.isGoogleDomain(domain))
    }

    @Test(arguments: [
        "notgoogle.com",
        "foogoogle.com",
        "google.com.evil.io",
        "google.evil.com",
        "googleusercontent.com",
        "youtube.com",
        "google.comm.au",          // "comm" is not a real second-level suffix
        "evil-google.com",
        "google",                  // bare label
        "com",
        "",
        ".",
    ])
    func rejectsLookalikes(_ domain: String) {
        #expect(!GoogleDomainMatcher.matches(domain), "expected \(domain) to be rejected")
    }
}
