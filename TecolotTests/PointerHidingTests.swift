import AppKit
import Testing
@testable import Tecolot

@MainActor
struct PointerHidingTests {
    @Test func enabledTextFromNonRepeatingKeyDownHidesPointer() {
        #expect(shouldHidePointerWhileTyping(
            enabled: true,
            insertedText: "a",
            eventType: .keyDown,
            isRepeat: false
        ))
    }

    @Test func committedMultibyteTextHidesPointer() {
        #expect(shouldHidePointerWhileTyping(
            enabled: true,
            insertedText: "日本語",
            eventType: .keyDown,
            isRepeat: false
        ))
    }

    @Test func disabledSettingDoesNotHidePointer() {
        #expect(!shouldHidePointerWhileTyping(
            enabled: false,
            insertedText: "a",
            eventType: .keyDown,
            isRepeat: false
        ))
    }

    @Test func emptyTextDoesNotHidePointer() {
        #expect(!shouldHidePointerWhileTyping(
            enabled: true,
            insertedText: "",
            eventType: .keyDown,
            isRepeat: false
        ))
    }

    @Test func missingCurrentEventDoesNotHidePointer() {
        #expect(!shouldHidePointerWhileTyping(
            enabled: true,
            insertedText: "a",
            eventType: nil,
            isRepeat: false
        ))
    }

    @Test(arguments: [NSEvent.EventType.keyUp, .leftMouseDown])
    func nonKeyDownEventDoesNotHidePointer(eventType: NSEvent.EventType) {
        #expect(!shouldHidePointerWhileTyping(
            enabled: true,
            insertedText: "a",
            eventType: eventType,
            isRepeat: false
        ))
    }

    @Test func repeatedKeyDownDoesNotHidePointer() {
        #expect(!shouldHidePointerWhileTyping(
            enabled: true,
            insertedText: "a",
            eventType: .keyDown,
            isRepeat: true
        ))
    }

    @Test func nsStringInputIsAccepted() {
        #expect(shouldHidePointerWhileTyping(
            enabled: true,
            insertedText: NSString(string: "text"),
            eventType: .keyDown,
            isRepeat: false
        ))
    }

    @Test func unsupportedInputIsIgnored() {
        #expect(!shouldHidePointerWhileTyping(
            enabled: true,
            insertedText: 42,
            eventType: .keyDown,
            isRepeat: false
        ))
    }
}
