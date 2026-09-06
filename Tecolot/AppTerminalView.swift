//
//  AppTerminalView.swift
//  Tecolot
//

import AppKit
import Foundation
import os
import SwiftTerm

/// Stores a main-actor callback behind a stable object reference.
///
/// Do not store the function directly in the generic lock. A generic `inout`
/// read can write a new reabstraction thunk back to the stored function. Each
/// read can then add a thunk and create an unbounded call and release chain.
nonisolated final class LockedMainActorCallback<Input: Sendable>: Sendable {
    private final class Callback: Sendable {
        let body: @MainActor @Sendable (Input) -> Void

        init(_ body: @escaping @MainActor @Sendable (Input) -> Void) {
            self.body = body
        }
    }

    private let callback = OSAllocatedUnfairLock<Callback?>(initialState: nil)

    func replace(with body: (@MainActor @Sendable (Input) -> Void)?) {
        let next = body.map(Callback.init)
        callback.withLock { $0 = next }
    }

    var current: (@MainActor @Sendable (Input) -> Void)? {
        callback.withLock { $0 }?.body
    }
}

private final class TerminalSessionEventDelivery: Sendable {
    private enum Event: Sendable {
        case bell
        case output
    }

    private let handler = LockedMainActorCallback<Event>()
    private let lastOutputNotification = OSAllocatedUnfairLock(initialState: Date.distantPast)

    @MainActor
    func setController(_ controller: TerminalSessionController?) {
        handler.replace { [weak controller] event in
            switch event {
            case .bell:
                controller?.noteBell()
            case .output:
                controller?.noteOutputActivity()
            }
        }
    }

    nonisolated func sendBell() {
        guard let handler = handler.current else { return }
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
        guard shouldNotify, let handler = handler.current else { return }
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

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self,
           window?.makeFirstResponder(self) == true {
            sessionController?.didBecomeFocused()
        }
        super.mouseDown(with: event)
    }

    /// Uses the current terminal-driver control bytes when SwiftTerm filters
    /// text before it sends a paste to the PTY.
    nonisolated override func terminalControlBytesForPaste(source: Terminal) -> Set<UInt8> {
        process?.terminalControlBytesForPaste()
            ?? TerminalPasteControls.approximateTerminalControlBytes
    }
}
