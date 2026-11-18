import Foundation
import Testing
@testable import SealcallCore

struct ScrubTests {
    func run(_ text: String, _ secret: String) -> String {
        String(decoding: scrub(Data(text.utf8), secret: secret), as: UTF8.self)
    }

    @Test func replacesEveryOccurrence() {
        #expect(run("a KEY b KEYKEY c", "KEY") == "a <redacted> b <redacted><redacted> c")
    }

    @Test func leavesOtherTextAlone() {
        #expect(run("nothing here", "KEY") == "nothing here")
        #expect(run("", "KEY") == "")
    }

    @Test func handlesKeyAtEdges() {
        #expect(run("KEY", "KEY") == "<redacted>")
        #expect(run("KEYx", "KEY") == "<redacted>x")
    }

    @Test func worksOnBinary() {
        let data = Data([0, 0xFF]) + Data("KEY".utf8) + Data([0xFE])
        #expect(scrub(data, secret: "KEY") == Data([0, 0xFF]) + redacted + Data([0xFE]))
    }

    @Test func worksOnSlices() {
        let data = Data("xxKEYyy".utf8).dropFirst(2)
        #expect(scrub(data, secret: "KEY") == redacted + Data("yy".utf8))
    }
}
