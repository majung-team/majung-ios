import Foundation
import XCTest
@testable import Majung

@MainActor
final class PickupTrackerTests: XCTestCase {
    private enum StubError: Error {
        case networkDown
        case sessionLost
    }

    private let initialPlace = PickupPlace(label: "왕십리역 1번 출구", latitude: 37.5612, longitude: 127.0370)
    private let updatedPlace = PickupPlace(label: "왕십리역 6번 출구", latitude: 37.5620, longitude: 127.0385)

    private func makeSnapshot(
        status: PickupSnapshot.Status = .active,
        place: PickupPlace? = PickupPlace(label: "왕십리역 1번 출구", latitude: 37.5612, longitude: 127.0370),
        placeVersion: Int = 1,
        ready: Bool = false,
        readinessSequence: Int = 1,
        readinessReceivedSequence: Int = 0,
        vehicleName: String? = "아이오닉 5 · 12가 3456"
    ) -> PickupSnapshot {
        PickupSnapshot(
            pickupId: UUID(),
            status: status,
            place: place,
            placeVersion: placeVersion,
            participant: PickupSnapshot.Participant(
                readiness: ready ? "READY" : "NOT_READY",
                readinessSequence: readinessSequence,
                readinessReceivedSequence: readinessReceivedSequence
            ),
            placeProposal: nil,
            quickMessage: nil,
            vehicleName: vehicleName
        )
    }

    private func makeVehicle(
        freshness: String = "FRESH",
        validForMillis: Int = 10_000,
        placeVersion: Int = 1
    ) -> PickupVehicle {
        PickupVehicle(
            freshness: freshness,
            latitude: 37.5600,
            longitude: 127.0360,
            durationSeconds: 180,
            validForMillis: validForMillis,
            ageMillis: 500,
            placeVersion: placeVersion
        )
    }

    func testVehicleValidityWindowAndInvalidationOnPlaceVersionChange() {
        let tracker = PickupTracker()
        let start = ContinuousClock.now
        let snap1 = makeSnapshot(place: initialPlace, placeVersion: 1)
        let freshVehicle = makeVehicle(validForMillis: 5_000, placeVersion: 1)

        tracker.applyExternal(snap1, vehicle: freshVehicle, startedAt: start)
        XCTAssertNotNil(tracker.currentVehicle(at: start))
        XCTAssertNotNil(tracker.currentVehicle(at: start.advanced(by: .milliseconds(4_999))))
        XCTAssertNil(tracker.currentVehicle(at: start.advanced(by: .milliseconds(5_000))))

        // Stale or mismatched placeVersion vehicle is ignored
        tracker.applyExternal(snap1, vehicle: makeVehicle(freshness: "STALE", placeVersion: 1), startedAt: start)
        XCTAssertNil(tracker.currentVehicle(at: start))

        tracker.applyExternal(snap1, vehicle: makeVehicle(validForMillis: 5_000, placeVersion: 2), startedAt: start)
        XCTAssertNil(tracker.currentVehicle(at: start))

        // Valid vehicle cleared immediately when placeVersion changes without new position
        tracker.applyExternal(snap1, vehicle: freshVehicle, startedAt: start)
        XCTAssertNotNil(tracker.currentVehicle(at: start))

        let snap2 = makeSnapshot(place: updatedPlace, placeVersion: 2)
        tracker.applyExternal(snap2, vehicle: nil, startedAt: start)
        XCTAssertNil(tracker.currentVehicle(at: start))
        XCTAssertEqual(tracker.lastPlace, updatedPlace)
    }

    func testCompletionRetainsLastPlaceAndVehicleNameUntilReset() {
        let tracker = PickupTracker()
        var terminalCallbacks = 0
        tracker.configure(
            PickupTracker.Backend(
                refresh: { (self.makeSnapshot(), nil) },
                setReady: { _, _ in self.makeSnapshot() },
                propose: { _ in self.makeSnapshot() },
                withdraw: { self.makeSnapshot() },
                sendMessage: { _ in self.makeSnapshot() },
                isSessionLost: { _ in false },
                onSessionLost: {},
                onTerminal: { terminalCallbacks += 1 },
                formatError: { _ in "error" },
                lostMessage: "lost"
            )
        )

        tracker.applyExternal(
            makeSnapshot(status: .active, place: initialPlace, vehicleName: "흰색 아이오닉 5"),
            vehicle: makeVehicle()
        )
        XCTAssertEqual(tracker.lastPlace, initialPlace)
        XCTAssertEqual(tracker.lastVehicleName, "흰색 아이오닉 5")

        let terminalSnapshot = makeSnapshot(status: .completed, place: nil, vehicleName: nil)
        tracker.applyExternal(terminalSnapshot, vehicle: nil)

        XCTAssertEqual(terminalCallbacks, 1)
        XCTAssertNil(tracker.vehicle)
        XCTAssertEqual(tracker.lastPlace, initialPlace)
        XCTAssertEqual(tracker.lastVehicleName, "흰색 아이오닉 5")

        tracker.resetState()
        XCTAssertNil(tracker.snapshot)
        XCTAssertNil(tracker.lastPlace)
        XCTAssertNil(tracker.lastVehicleName)
        XCTAssertNil(tracker.vehicle)
    }

    func testSetReadyResendReadyAndSendMessageValidation() async {
        let tracker = PickupTracker()
        var readyCalls: [(Bool, Int)] = []
        var sentMessages: [String] = []

        tracker.configure(
            PickupTracker.Backend(
                refresh: { (self.makeSnapshot(), nil) },
                setReady: { ready, seq in
                    readyCalls.append((ready, seq))
                    return self.makeSnapshot(ready: ready, readinessSequence: seq, readinessReceivedSequence: 0)
                },
                propose: { _ in self.makeSnapshot() },
                withdraw: { self.makeSnapshot() },
                sendMessage: { text in
                    sentMessages.append(text)
                    return self.makeSnapshot(ready: true, readinessSequence: 3, readinessReceivedSequence: 3)
                },
                isSessionLost: { _ in false },
                onSessionLost: {},
                onTerminal: {},
                formatError: { _ in "error" },
                lostMessage: "lost"
            )
        )

        tracker.applyExternal(makeSnapshot(ready: false, readinessSequence: 1), vehicle: nil)

        // No-op when already not ready; resendReady also no-op before ready
        await tracker.setReady(false)
        await tracker.resendReady()
        XCTAssertTrue(readyCalls.isEmpty)

        // Transition false -> true sends sequence + 1
        await tracker.setReady(true)
        XCTAssertEqual(readyCalls.count, 1)
        XCTAssertEqual(readyCalls.first?.0, true)
        XCTAssertEqual(readyCalls.first?.1, 2)

        // resendReady advances sequence again while keeping ready = true
        await tracker.resendReady()
        XCTAssertEqual(readyCalls.count, 2)
        XCTAssertEqual(readyCalls.last?.0, true)
        XCTAssertEqual(readyCalls.last?.1, 3)

        // Empty or >50 UTF-16 message does not submit
        tracker.messageDraft = "   \n "
        await tracker.sendMessage()
        tracker.messageDraft = String(repeating: "가", count: 51)
        await tracker.sendMessage()
        XCTAssertTrue(sentMessages.isEmpty)

        // Valid trimmed message submits, clears draft, marks messageSent until edited
        tracker.messageDraft = "  지금 내려가요  "
        await tracker.sendMessage()
        XCTAssertEqual(sentMessages, ["지금 내려가요"])
        XCTAssertEqual(tracker.messageDraft, "")
        XCTAssertTrue(tracker.messageSent)

        tracker.messageDraft = "추가"
        XCTAssertFalse(tracker.messageSent)
    }

    func testRefreshErrorAndSessionLossHandling() async {
        let tracker = PickupTracker()
        var currentError: StubError = .networkDown
        var sessionLostCount = 0

        tracker.configure(
            PickupTracker.Backend(
                refresh: { throw currentError },
                setReady: { _, _ in self.makeSnapshot() },
                propose: { _ in self.makeSnapshot() },
                withdraw: { self.makeSnapshot() },
                sendMessage: { _ in self.makeSnapshot() },
                isSessionLost: { ($0 as? StubError) == .sessionLost },
                onSessionLost: { sessionLostCount += 1 },
                onTerminal: {},
                formatError: { _ in "formatted" },
                lostMessage: "세션이 종료되었어요"
            )
        )

        tracker.applyExternal(makeSnapshot(), vehicle: makeVehicle())
        XCTAssertNotNil(tracker.vehicle)

        await tracker.refresh()
        XCTAssertNil(tracker.vehicle)
        XCTAssertTrue(tracker.connectionProblem)
        XCTAssertEqual(sessionLostCount, 0)

        currentError = .sessionLost
        await tracker.refresh()
        XCTAssertEqual(sessionLostCount, 1)
        XCTAssertNil(tracker.snapshot)
        XCTAssertNil(tracker.lastPlace)
        XCTAssertFalse(tracker.connectionProblem)
        XCTAssertEqual(tracker.error, "세션이 종료되었어요")
    }

    func testSuggestAndWithdrawProposalUpdateSnapshot() async {
        let tracker = PickupTracker()
        var proposedPlaces: [PickupPlace] = []
        var withdrawCount = 0

        let withProposal = PickupSnapshot(
            pickupId: UUID(),
            status: .active,
            place: initialPlace,
            placeVersion: 1,
            participant: PickupSnapshot.Participant(readiness: "NOT_READY", readinessSequence: 1, readinessReceivedSequence: 1),
            placeProposal: PickupSnapshot.Proposal(place: updatedPlace, proposedBy: "PASSENGER"),
            quickMessage: nil,
            vehicleName: "아이오닉 5"
        )
        let withdrawn = makeSnapshot(place: initialPlace, placeVersion: 1)

        tracker.configure(
            PickupTracker.Backend(
                refresh: { (self.makeSnapshot(), nil) },
                setReady: { _, _ in self.makeSnapshot() },
                propose: { place in
                    proposedPlaces.append(place)
                    return withProposal
                },
                withdraw: {
                    withdrawCount += 1
                    return withdrawn
                },
                sendMessage: { _ in self.makeSnapshot() },
                isSessionLost: { _ in false },
                onSessionLost: {},
                onTerminal: {},
                formatError: { _ in "error" },
                lostMessage: "lost"
            )
        )

        tracker.applyExternal(makeSnapshot(place: initialPlace, placeVersion: 1), vehicle: nil)
        let ok = await tracker.suggest(updatedPlace)
        XCTAssertTrue(ok)
        XCTAssertEqual(proposedPlaces, [updatedPlace])
        XCTAssertEqual(tracker.snapshot?.placeProposal?.place, updatedPlace)

        await tracker.withdrawProposal()
        XCTAssertEqual(withdrawCount, 1)
        XCTAssertNil(tracker.snapshot?.placeProposal)
    }

    private func makeTracker(
        refresh: @escaping () async throws -> (PickupSnapshot, PickupVehicle?),
        setReady: ((Bool, Int) async throws -> PickupSnapshot)? = nil
    ) -> PickupTracker {
        let tracker = PickupTracker()
        tracker.configure(PickupTracker.Backend(
            refresh: refresh,
            setReady: setReady ?? { ready, sequence in
                self.makeSnapshot(ready: ready, readinessSequence: sequence)
            },
            propose: { _ in self.makeSnapshot() },
            withdraw: { self.makeSnapshot() },
            sendMessage: { _ in self.makeSnapshot() },
            isSessionLost: { _ in false },
            onSessionLost: {},
            onTerminal: {},
            formatError: { _ in "error" },
            lostMessage: "lost"
        ))
        return tracker
    }

    func testRefreshDuringInFlightReadFetchesLatestTerminalState() async throws {
        let started = expectation(description: "First snapshot request started")
        var response: CheckedContinuation<(PickupSnapshot, PickupVehicle?), Error>?
        var calls = 0
        let tracker = makeTracker(refresh: {
            calls += 1
            if calls == 1 {
                return try await withCheckedThrowingContinuation { continuation in
                    response = continuation
                    started.fulfill()
                }
            }
            return (self.makeSnapshot(status: .completed, place: nil, vehicleName: nil), nil)
        })
        tracker.applyExternal(makeSnapshot(), vehicle: makeVehicle())
        let firstRefresh = Task { await tracker.refresh() }
        await fulfillment(of: [started], timeout: 5)

        // A terminal change arrives while the earlier ARRIVED read is still in flight.
        await tracker.refresh()
        await tracker.refresh()
        try XCTUnwrap(response).resume(returning: (makeSnapshot(status: .arrived), makeVehicle()))
        await firstRefresh.value

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(tracker.snapshot?.status, .completed)
        XCTAssertNil(tracker.vehicle)
        XCTAssertEqual(tracker.lastPlace, initialPlace)
    }

    func testRefreshDuringReadinessWriteRunsAfterWriteCompletes() async throws {
        let started = expectation(description: "Readiness request started")
        var response: CheckedContinuation<PickupSnapshot, Error>?
        var reads = 0
        let tracker = makeTracker(refresh: {
            reads += 1
            return (self.makeSnapshot(status: .completed, place: nil, vehicleName: nil), nil)
        }, setReady: { _, _ in
            try await withCheckedThrowingContinuation { continuation in
                response = continuation
                started.fulfill()
            }
        })
        tracker.applyExternal(makeSnapshot(), vehicle: makeVehicle())
        let write = Task { await tracker.setReady(true) }
        await fulfillment(of: [started], timeout: 5)

        await tracker.refresh()
        await tracker.refresh()
        try XCTUnwrap(response).resume(returning: makeSnapshot(ready: true))
        await write.value

        XCTAssertEqual(reads, 1)
        XCTAssertEqual(tracker.snapshot?.status, .completed)
        XCTAssertFalse(tracker.busy)
        XCTAssertNil(tracker.vehicle)
    }

    func testResetDiscardsQueuedRefreshFromPreviousSession() async throws {
        let started = expectation(description: "Previous session request started")
        var response: CheckedContinuation<(PickupSnapshot, PickupVehicle?), Error>?
        var calls = 0
        let tracker = makeTracker(refresh: {
            calls += 1
            return try await withCheckedThrowingContinuation { continuation in
                response = continuation
                started.fulfill()
            }
        })
        tracker.applyExternal(makeSnapshot(), vehicle: makeVehicle())
        let previousRefresh = Task { await tracker.refresh() }
        await fulfillment(of: [started], timeout: 5)
        await tracker.refresh()
        tracker.resetState()
        try XCTUnwrap(response).resume(returning: (makeSnapshot(status: .arrived), makeVehicle()))
        await previousRefresh.value

        XCTAssertEqual(calls, 1)
        XCTAssertNil(tracker.snapshot)
        XCTAssertNil(tracker.vehicle)
    }
}
