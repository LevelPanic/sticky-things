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
        handle.attach(owner: ObjectIdentifier(a), token: UUID(), save: { saved.append("a") }, cancel: {}, focus: {})
        handle.attach(owner: ObjectIdentifier(b), token: UUID(), save: { saved.append("b") }, cancel: {}, focus: {})
        handle.detach(owner: ObjectIdentifier(a)) // A finishes after B started
        XCTAssertTrue(handle.isActive)
        handle.save()
        XCTAssertEqual(saved, ["b"])
        handle.detach(owner: ObjectIdentifier(b))
        XCTAssertFalse(handle.isActive)
        handle.save()
        XCTAssertEqual(saved, ["b"], "nothing attached, nothing happens")
    }

    /// A growing card in a lazy list can make SwiftUI build two platform views for one edit.
    /// The duplicate going away must not end the edit, and Save must still find the survivor.
    func testDuplicateEditorForTheSameEditLeavesTheSurvivorInCharge() {
        let handle = InlineEditHandle()
        var saved: [String] = []
        let token = UUID()
        let first = NSObject(), second = NSObject()
        handle.attach(owner: ObjectIdentifier(first), token: token, save: { saved.append("first") }, cancel: {}, focus: {})
        handle.attach(owner: ObjectIdentifier(second), token: token, save: { saved.append("second") }, cancel: {}, focus: {})
        XCTAssertTrue(handle.hasOtherEditor(owner: ObjectIdentifier(second), token: token))
        handle.detach(owner: ObjectIdentifier(second)) // the duplicate resigns first
        XCTAssertTrue(handle.isActive, "the survivor is still editing")
        XCTAssertFalse(handle.hasOtherEditor(owner: ObjectIdentifier(first), token: token))
        handle.save()
        XCTAssertEqual(saved, ["first"], "Save reaches the surviving editor")

        // An editor from a different edit is not a duplicate: it must not keep this one alive.
        let other = UUID()
        let third = NSObject()
        handle.attach(owner: ObjectIdentifier(third), token: other, save: {}, cancel: {}, focus: {})
        XCTAssertFalse(handle.hasOtherEditor(owner: ObjectIdentifier(first), token: token))
        handle.detach(owner: ObjectIdentifier(first))
        XCTAssertTrue(handle.isActive)
    }
}
