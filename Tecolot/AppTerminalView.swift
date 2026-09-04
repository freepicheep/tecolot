//
//  AppTerminalView.swift
//  Tecolot
//

import AppKit
import Foundation
import os
import SwiftTerm

func shouldHidePointerWhileTyping(
    enabled: Bool,
    insertedText: Any,
    eventType: NSEvent.EventType?,
    isRepeat: Bool
) -> Bool {
    guard enabled,
          let text = insertedText as? NSString,
          text.length > 0,
          eventType == .keyDown,
          !isRepeat else {
        return false
    }
    return true
}

private final class TerminalSessionEventDelivery: Sendable {
    private enum Event: Sendable {
        case bell
        case output
    }

    private let handler = OSAllocatedUnfairLock<(@MainActor @Sendable (Event) -> Void)?>(
        initialState: nil)
    private let lastOutputNotification = OSAllocatedUnfairLock(initialState: Date.distantPast)

    @MainActor
    func setController(_ controller: TerminalSessionController?) {
        handler.withLock { storedHandler in
            storedHandler = { [weak controller] event in
                switch event {
                case .bell:
                    controller?.noteBell()
                case .output:
                    controller?.noteOutputActivity()
                }
            }
        }
    }

    nonisolated func sendBell() {
        guard let handler = handler.withLock({ $0 }) else { return }
        Task { @MainActor in
            handler(.bell)
        }
    }

    nonisolated func sendOutput() {
        let shouldNotify = lastOutputNotification.withLock { lastNotification in
            let now = Date()
            guard now.timeIntervalSince(lastNotification) > 0.25 else { return false }
            lastNotification = now
            return true
        }
        guard shouldNotify, let handler = handler.withLock({ $0 }) else { return }
        Task { @MainActor in
            handler(.output)
        }
    }
}

final class AppTerminalView: LocalProcessTerminalView {
    weak var sessionController: TerminalSessionController? {
        didSet {
            eventDelivery.setController(sessionController)
            setProcessOutputHandler { [eventDelivery] in
                eventDelivery.sendOutput()
            }
        }
    }

    nonisolated private let eventDelivery = TerminalSessionEventDelivery()

    nonisolated override func bell(source: Terminal) {
        super.bell(source: source)
        eventDelivery.sendBell()
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let event = NSApp.currentEvent
        if shouldHidePointerWhileTyping(
            enabled: sessionController?.profile.hidePointerWhileTyping == true,
            insertedText: string,
            eventType: event?.type,
            isRepeat: event?.isARepeat ?? false
        ) {
            // Hide for a non-repeating press that commits UTF-8 text,
            // not for every control sequence that may be sent to the PTY.
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Uses the current terminal-driver control bytes when SwiftTerm filters
    /// text before it sends a paste to the PTY.
    nonisolated override func terminalControlBytesForPaste(source: Terminal) -> Set<UInt8> {
        process?.terminalControlBytesForPaste()
            ?? TerminalPasteControls.approximateTerminalControlBytes
    }
}
