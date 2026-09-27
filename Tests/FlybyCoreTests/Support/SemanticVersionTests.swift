import Testing
@testable import FlybyCore

@Suite struct SemanticVersionTests {
    @Test func parsesReleaseTags() throws {
        let v = try #require(SemanticVersion("v1.2.3"))
        #expect(v == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion("0.3")?.description == "0.3.0")
        #expect(SemanticVersion("1.3.0-beta.2")?.prerelease == ["beta", "2"])
        #expect(SemanticVersion("1.0.0+build.7") == SemanticVersion(major: 1, minor: 0, patch: 0))
    }

    @Test func rejectsTagsThatWereNeverVersions() {
        for tag in ["Golden", "beta", "", "v", "1", "1.2.3.4", "1..3", "1.2.x", "1.2.3-", "1.2.3-beta..1", "١.٢.٣"] {
            #expect(SemanticVersion(tag) == nil, "\(tag) should not parse")
        }
    }

    @Test func ordersBySemVerPrecedence() throws {
        let ordered = ["0.2.0", "0.3.0-alpha", "0.3.0-alpha.1", "0.3.0-alpha.beta", "0.3.0-beta",
                       "0.3.0-beta.2", "0.3.0-beta.11", "0.3.0-rc.1", "0.3.0", "0.10.0", "1.0.0"]
        let versions = try ordered.map { try #require(SemanticVersion($0)) }
        #expect(versions == versions.sorted())
        for (a, b) in zip(versions, versions.dropFirst()) { #expect(a < b) }
    }
}
