import XCTest
@testable import StickyDesign

@MainActor
final class InlineEditHandleTests: XCTestCase {
    /// One handle serves the whole list: an editor that finishes late must not unhook the one
    /// that replaced it.
    func testOnlyTheCurrentEditorResponds() {
        let handle = InlineEditHandle()
        XCTAssertFalse(handle.isActive)
        var saved: [String] = []
        let a = NSObject(), b = NSObject()
        handle.attach(owner: ObjectIdentifier(a), save: { saved.append("a") }, cancel: {}, focus: {})
        handle.attach(owner: ObjectIdentifier(b), save: { saved.append("b") }, cancel: {}, focus: {})
        handle.detach(owner: ObjectIdentifier(a)) // A finishes after B started
        XCTAssertTrue(handle.isActive)
        handle.save()
        XCTAssertEqual(saved, ["b"])
        handle.detach(owner: ObjectIdentifier(b))
        XCTAssertFalse(handle.isActive)
        handle.save()
        XCTAssertEqual(saved, ["b"], "nothing attached, nothing happens")
    }
}
