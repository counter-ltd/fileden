import Testing
import Foundation
@testable import FileDenCore

@Suite("ShelfItem")
struct ShelfItemTests {
    @Test func nameFromURL() {
        let url = URL(fileURLWithPath: "/tmp/hello.txt")
        let item = ShelfItem(url: url)
        #expect(item.name == "hello.txt")
    }

    @Test func uniqueIDs() {
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        let a = ShelfItem(url: url)
        let b = ShelfItem(url: url)
        #expect(a.id != b.id)
    }
}
