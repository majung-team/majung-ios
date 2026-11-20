import ActivityKit
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
        durationSeconds: Int? = 180,
        validForMillis: Int = 10_000,
        placeVersion: Int = 1
    ) -> PickupVehicle {
        PickupVehicle(
            freshness: freshness,
            latitude: 37.5600,
            longitude: 127.0360,
            durationSeconds: durationSeconds,
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

    func testRefreshFailureRetainsLastCheckAndRecoveryResetsWithSession() async {
        let tracker = PickupTracker()
        var failing = false
        tracker.configure(PickupTracker.Backend(
            refresh: {
                if failing { throw StubError.networkDown }
                return (self.makeSnapshot(), self.makeVehicle())
            },
            setReady: { _, _ in self.makeSnapshot() },
            propose: { _ in self.makeSnapshot() },
            withdraw: { self.makeSnapshot() },
            sendMessage: { _ in self.makeSnapshot() },
            isSessionLost: { _ in false }, onSessionLost: {}, onTerminal: {},
            formatError: { _ in "network" }, lostMessage: "expired"
        ))
        await tracker.refresh()
        let checked = tracker.lastRefreshedAt
        XCTAssertNotNil(checked)
        XCTAssertNil(tracker.reconnectedAt)
        failing = true
        await tracker.refresh()
        XCTAssertTrue(tracker.connectionProblem)
        XCTAssertNil(tracker.currentVehicle())
        XCTAssertEqual(tracker.lastRefreshedAt, checked)
        failing = false
        await tracker.refresh()
        XCTAssertFalse(tracker.connectionProblem)
        XCTAssertNotNil(tracker.reconnectedAt)
        XCTAssertNotNil(tracker.currentVehicle())
        tracker.resetState()
        XCTAssertNil(tracker.lastRefreshedAt)
        XCTAssertNil(tracker.reconnectedAt)
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

    private func makeViewModelTransport(
        preview: @escaping (PickupInvitation) async throws -> String = { _ in "왕십리역 1번 출구" },
        join: @escaping (PickupInvitation) async throws -> PickupSession = { invite in
            PickupSession(id: invite.id, token: "participant-token")
        },
        snapshot: @escaping (PickupSession) async throws -> PickupSnapshot,
        vehicle: @escaping (PickupSession) async throws -> PickupVehicle,
        leaveWaiting: @escaping (PickupSession) async throws -> Void = { _ in },
        saveSession: @escaping (PickupSession) throws -> Void = { _ in },
        clearSession: @escaping () -> Void = {}
    ) -> PickupViewModel.Transport {
        PickupViewModel.Transport(
            preview: preview,
            join: join,
            snapshot: snapshot,
            vehicle: vehicle,
            readiness: { _, _, _ in self.makeSnapshot() },
            propose: { _, _ in self.makeSnapshot() },
            withdraw: { _ in self.makeSnapshot() },
            message: { _, _ in self.makeSnapshot() },
            leaveWaiting: leaveWaiting,
            registerArrivalPush: { _, _ in },
            streamEvents: { _, _, _ in },
            saveSession: saveSession,
            clearSession: clearSession
        )
    }

    func testLeaveWaitingRetainsSessionOnFailureAndClearsItOnRetry() async {
        let session = PickupSession(id: UUID(), token: "fixture")
        let waiting = makeSnapshot(status: .waiting)
        var attempts = 0
        var checks = 0
        var clears = 0
        let model = PickupViewModel(transport: makeViewModelTransport(
            snapshot: { _ in checks += 1; return waiting },
            vehicle: { _ in throw StubError.networkDown },
            leaveWaiting: { _ in
                attempts += 1
                if attempts == 1 { throw StubError.networkDown }
            },
            clearSession: { clears += 1 }
        ), initialSession: session)
        model.tracker.applyExternal(waiting, vehicle: nil)
        await model.leaveWaiting()
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(model.session?.id, session.id)
        XCTAssertNotNil(model.tracker.error)
        XCTAssertEqual(clears, 0)
        await model.leaveWaiting()
        XCTAssertNil(model.session)
        XCTAssertNil(model.tracker.snapshot)
        XCTAssertEqual(clears, 1)
    }

    func testLostLeaveResponseReconcilesWithRevokedParticipantSession() async {
        let session = PickupSession(id: UUID(), token: "fixture")
        var clears = 0
        let model = PickupViewModel(transport: makeViewModelTransport(
            snapshot: { _ in
                throw PickupAPI.Failure(status: 403, code: "FORBIDDEN", message: "이 픽업에 접근할 수 없습니다.")
            },
            vehicle: { _ in throw StubError.networkDown },
            leaveWaiting: { _ in throw StubError.networkDown },
            clearSession: { clears += 1 }
        ), initialSession: session)
        model.tracker.applyExternal(makeSnapshot(status: .waiting), vehicle: nil)
        await model.leaveWaiting()
        XCTAssertNil(model.session)
        XCTAssertEqual(model.page, .entry)
        XCTAssertEqual(clears, 1)
    }

    func testSlowVehicleResponseHasSameRemainingLifetimeOnLockScreen() throws {
        let activity = PickupLiveActivityService(isEnabled: { true }, upsertHandler: { _, _ in }, endAllHandler: {})
        let tracker = PickupTracker(liveActivity: activity)
        let start = ContinuousClock.now.advanced(by: .seconds(-8))
        let snapshot = makeSnapshot()
        tracker.applyExternal(snapshot, vehicle: makeVehicle(validForMillis: 10_000), startedAt: start)
        XCTAssertEqual(tracker.vehicleExpiresAt, start.advanced(by: .seconds(10)))
        let deadline = try XCTUnwrap(activity.currentState?.vehicleFreshUntil)
        XCTAssertEqual(deadline.timeIntervalSinceNow, 2, accuracy: 0.5)
        tracker.applyExternal(snapshot, vehicle: makeVehicle(validForMillis: 5_000), startedAt: start)
        XCTAssertNil(tracker.currentVehicle())
        XCTAssertNil(activity.currentState?.vehicleFreshUntil)
    }

    func testJoinFetchesInitialSnapshotBeforeSwitchingToPickupPage() async throws {
        let snapshotStarted = expectation(description: "Initial snapshot started before page transition")
        var snapshotContinuation: CheckedContinuation<PickupSnapshot, Error>?
        var savedSessions: [PickupSession] = []
        let activeSnapshot = makeSnapshot(status: .active, place: initialPlace)
        let activeVehicle = makeVehicle()

        let viewModel = PickupViewModel(
            transport: makeViewModelTransport(
                snapshot: { _ in
                    try await withCheckedThrowingContinuation { continuation in
                        snapshotContinuation = continuation
                        snapshotStarted.fulfill()
                    }
                },
                vehicle: { _ in activeVehicle },
                saveSession: { savedSessions.append($0) }
            ),
            initialSession: nil
        )

        let inviteURL = "https://majung.cloud/#join/11111111-2222-4333-8444-555555555555/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm0123"
        await viewModel.openLink(inviteURL)
        XCTAssertEqual(viewModel.page, .invitation)
        XCTAssertEqual(viewModel.placeLabel, "왕십리역 1번 출구")

        let joinTask = Task { await viewModel.join() }
        await fulfillment(of: [snapshotStarted], timeout: 5)

        // While initial snapshot is in flight, page must remain .invitation instead of showing empty PickupView.
        XCTAssertEqual(viewModel.page, .invitation)
        XCTAssertNil(viewModel.tracker.snapshot)
        XCTAssertEqual(savedSessions.count, 1)

        try XCTUnwrap(snapshotContinuation).resume(returning: activeSnapshot)
        await joinTask.value

        XCTAssertEqual(viewModel.page, .pickup)
        XCTAssertEqual(viewModel.tracker.snapshot?.status, .active)
        XCTAssertEqual(viewModel.tracker.snapshot?.place, initialPlace)
        XCTAssertEqual(viewModel.tracker.vehicle?.durationSeconds, activeVehicle.durationSeconds)
        XCTAssertFalse(viewModel.busy)
    }

    func testJoinFallsBackToPickupPageWhenInitialSnapshotFails() async {
        let viewModel = PickupViewModel(
            transport: makeViewModelTransport(
                snapshot: { _ in throw StubError.networkDown },
                vehicle: { _ in self.makeVehicle() }
            ),
            initialSession: nil
        )

        let inviteURL = "https://majung.cloud/#join/11111111-2222-4333-8444-555555555555/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm0123"
        await viewModel.openLink(inviteURL)
        await viewModel.join()

        XCTAssertEqual(viewModel.page, .pickup)
        XCTAssertNotNil(viewModel.session)
        XCTAssertNil(viewModel.tracker.snapshot)
    }

    func testJoinWithCompletedSnapshotClearsSessionAndShowsSummary() async {
        var clearedCount = 0
        let viewModel = PickupViewModel(
            transport: makeViewModelTransport(
                snapshot: { _ in self.makeSnapshot(status: .completed, place: self.initialPlace, vehicleName: "아이오닉 5") },
                vehicle: { _ in self.makeVehicle() },
                clearSession: { clearedCount += 1 }
            ),
            initialSession: nil
        )

        let inviteURL = "https://majung.cloud/#join/11111111-2222-4333-8444-555555555555/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm0123"
        await viewModel.openLink(inviteURL)
        await viewModel.join()

        XCTAssertEqual(viewModel.page, .pickup)
        XCTAssertNil(viewModel.session)
        XCTAssertEqual(viewModel.tracker.snapshot?.status, .completed)
        XCTAssertEqual(clearedCount, 1)
    }

    func testLiveActivityStatePreservesCountdownAcrossSnapshotUpdatesAndClearsOnPlaceChangeOrArrival() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let activeSnapshot = makeSnapshot(status: .active, place: initialPlace, placeVersion: 1, ready: true, vehicleName: "최수빈 카니발")
        let freshVehicle = makeVehicle(durationSeconds: 240, validForMillis: 30_000, placeVersion: 1)

        let initialState = try XCTUnwrap(
            PickupLiveActivityService.makeState(
                snapshot: activeSnapshot,
                vehicle: freshVehicle,
                vehicleUpdatedAt: now,
                previousState: nil,
                now: now
            )
        )
        XCTAssertEqual(initialState.phase, .approaching)
        XCTAssertEqual(initialState.placeLabel, initialPlace.label)
        XCTAssertEqual(initialState.vehicleName, "최수빈 카니발")
        XCTAssertEqual(initialState.durationSeconds, 240)
        XCTAssertEqual(initialState.estimatedArrivalDate, now.addingTimeInterval(240))
        XCTAssertTrue(initialState.passengerReady)
        XCTAssertNotNil(initialState.activeTimerRange(at: now.addingTimeInterval(10)))
        XCTAssertEqual(initialState.etaSummaryText, "약 4분 후 도착 예정")

        // Snapshot-only update (e.g. background transition or readiness update before next vehicle poll) preserves active countdown.
        let tenSecondsLater = now.addingTimeInterval(10)
        let preservedState = try XCTUnwrap(
            PickupLiveActivityService.makeState(
                snapshot: activeSnapshot,
                vehicle: nil,
                vehicleUpdatedAt: nil,
                previousState: initialState,
                now: tenSecondsLater
            )
        )
        XCTAssertEqual(preservedState.estimatedArrivalDate, initialState.estimatedArrivalDate)
        XCTAssertEqual(preservedState.durationSeconds, 230)

        // Accepting a new place increments placeVersion and resets the previous place's countdown until new vehicle ETA arrives.
        let newPlaceSnapshot = makeSnapshot(status: .active, place: updatedPlace, placeVersion: 2, ready: true, vehicleName: "최수빈 카니발")
        let resetCountdownState = try XCTUnwrap(
            PickupLiveActivityService.makeState(
                snapshot: newPlaceSnapshot,
                vehicle: nil,
                vehicleUpdatedAt: nil,
                previousState: preservedState,
                now: tenSecondsLater
            )
        )
        XCTAssertEqual(resetCountdownState.placeLabel, updatedPlace.label)
        XCTAssertNil(resetCountdownState.estimatedArrivalDate)
        XCTAssertEqual(resetCountdownState.etaSummaryText, "도착 시간을 확인 중이에요")

        // Arrival switches phase to .arrived and clears countdown timer.
        let arrivedSnapshot = makeSnapshot(status: .arrived, place: updatedPlace, placeVersion: 2, ready: true, vehicleName: "최수빈 카니발")
        let arrivedState = try XCTUnwrap(
            PickupLiveActivityService.makeState(
                snapshot: arrivedSnapshot,
                vehicle: freshVehicle,
                vehicleUpdatedAt: tenSecondsLater,
                previousState: initialState,
                now: tenSecondsLater
            )
        )
        XCTAssertEqual(arrivedState.phase, .arrived)
        XCTAssertNil(arrivedState.estimatedArrivalDate)
        XCTAssertNil(arrivedState.activeTimerRange(at: tenSecondsLater))
        XCTAssertEqual(arrivedState.compactTrailingLabel, "도착")

        // Terminal state returns nil so Live Activity ends immediately.
        let completedSnapshot = makeSnapshot(status: .completed, place: updatedPlace, placeVersion: 2)
        XCTAssertNil(
            PickupLiveActivityService.makeState(
                snapshot: completedSnapshot,
                vehicle: nil,
                vehicleUpdatedAt: nil,
                previousState: arrivedState,
                now: tenSecondsLater
            )
        )
    }

    func testLiveActivityDropsExpiredAndExplicitlyStaleVehicleETA() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = makeSnapshot()
        let initial = try XCTUnwrap(PickupLiveActivityService.makeState(
            snapshot: snapshot, vehicle: makeVehicle(durationSeconds: 240, validForMillis: 5_000),
            vehicleUpdatedAt: now, previousState: nil, now: now
        ))
        for vehicle in [makeVehicle(freshness: "STALE"), makeVehicle(validForMillis: 0)] {
            let state = try XCTUnwrap(PickupLiveActivityService.makeState(
                snapshot: snapshot, vehicle: vehicle, vehicleUpdatedAt: now,
                previousState: initial, now: now.addingTimeInterval(1)
            ))
            XCTAssertNil(state.estimatedArrivalDate)
            XCTAssertNil(state.durationSeconds)
        }
        let expired = try XCTUnwrap(PickupLiveActivityService.makeState(
            snapshot: snapshot, vehicle: nil, vehicleUpdatedAt: nil,
            previousState: initial, now: now.addingTimeInterval(6)
        ))
        XCTAssertNil(expired.estimatedArrivalDate)
        XCTAssertNil(initial.activeTimerRange(at: now.addingTimeInterval(6)))
        let freshWithoutETA = try XCTUnwrap(PickupLiveActivityService.makeState(
            snapshot: snapshot, vehicle: makeVehicle(durationSeconds: nil), vehicleUpdatedAt: now,
            previousState: initial, now: now
        ))
        XCTAssertNil(freshWithoutETA.estimatedArrivalDate)
        XCTAssertEqual(freshWithoutETA.vehicleFreshUntil, now.addingTimeInterval(10))
    }

    func testLiveActivityRefreshesValidityWhenArrivalEstimateIsUnchanged() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = makeSnapshot()
        let refreshed = expectation(description: "Validity renewed with the same arrival estimate")
        refreshed.expectedFulfillmentCount = 2
        let service = PickupLiveActivityService(isEnabled: { true }, upsertHandler: { _, _ in
            refreshed.fulfill()
        }, endAllHandler: {})
        service.sync(snapshot: snapshot, vehicle: makeVehicle(durationSeconds: 240), vehicleUpdatedAt: now, now: now)
        service.sync(snapshot: snapshot, vehicle: makeVehicle(durationSeconds: 237),
                     vehicleUpdatedAt: now.addingTimeInterval(3), now: now.addingTimeInterval(3))
        await fulfillment(of: [refreshed], timeout: 2)
    }

    func testTrackerSyncsAndEndsLiveActivityOnlyForOwnedPickup() async {
        var upserts: [(String, PickupLiveActivityAttributes.ContentState)] = []
        var endCount = 0
        let upsertExp = expectation(description: "Initial upsert")
        upsertExp.expectedFulfillmentCount = 2
        let endExp = expectation(description: "Terminal end")

        let service = PickupLiveActivityService(
            isEnabled: { true },
            upsertHandler: { key, state in
                upserts.append((key, state))
                upsertExp.fulfill()
            },
            endAllHandler: {
                endCount += 1
                endExp.fulfill()
            }
        )

        let trackerA = PickupTracker(liveActivity: service)
        let trackerB = PickupTracker(liveActivity: service)
        let pickupIdA = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!

        trackerA.applyExternal(
            PickupSnapshot(
                pickupId: pickupIdA,
                status: .active,
                place: initialPlace,
                placeVersion: 1,
                participant: PickupSnapshot.Participant(readiness: "NOT_READY", readinessSequence: 1, readinessReceivedSequence: 1),
                placeProposal: nil,
                quickMessage: nil,
                vehicleName: "아이오닉 5"
            ),
            vehicle: makeVehicle(durationSeconds: 180, placeVersion: 1)
        )

        // Resetting an unrelated empty tracker must not end trackerA's Live Activity.
        trackerB.resetState()
        XCTAssertEqual(service.currentPickupKey, pickupIdA.uuidString.lowercased())

        // Clearing vehicle on background transition keeps the Live Activity alive.
        trackerA.clearVehicle()
        XCTAssertNotNil(service.currentState)

        // Terminal update on trackerA ends the Live Activity.
        trackerA.applyExternal(
            PickupSnapshot(
                pickupId: pickupIdA,
                status: .completed,
                place: initialPlace,
                placeVersion: 1,
                participant: nil,
                placeProposal: nil,
                quickMessage: nil,
                vehicleName: "아이오닉 5"
            ),
            vehicle: nil
        )

        await fulfillment(of: [upsertExp, endExp], timeout: 5)
        XCTAssertEqual(upserts.count, 2)
        XCTAssertEqual(upserts.last?.1.durationSeconds, 180)
        XCTAssertEqual(endCount, 1)
        XCTAssertNil(service.currentState)
    }

    func testApproachingSoonFormattingAndArrivalBoardingNotification() async {
        XCTAssertTrue(MajungFormatting.isApproachingSoon(makeVehicle(durationSeconds: 0)))
        XCTAssertTrue(MajungFormatting.isApproachingSoon(makeVehicle(durationSeconds: 180)))
        XCTAssertFalse(MajungFormatting.isApproachingSoon(makeVehicle(durationSeconds: 181)))
        XCTAssertFalse(MajungFormatting.isApproachingSoon(makeVehicle(durationSeconds: nil)))
        XCTAssertFalse(MajungFormatting.isApproachingSoon(nil))

        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNotNil(MajungFormatting.lastCheckedText(updatedAt: checkedAt, refreshedAt: nil, now: checkedAt))
        XCTAssertNotNil(MajungFormatting.lastCheckedText(updatedAt: nil, refreshedAt: checkedAt, now: checkedAt))
        XCTAssertNil(MajungFormatting.lastCheckedText(updatedAt: nil, refreshedAt: nil, now: checkedAt))

        var sentMessages: [String] = []
        let tracker = PickupTracker()
        tracker.configure(PickupTracker.Backend(
            refresh: { (self.makeSnapshot(status: .arrived), nil) },
            setReady: { _, _ in self.makeSnapshot() },
            propose: { _ in self.makeSnapshot() },
            withdraw: { self.makeSnapshot() },
            sendMessage: { text in
                sentMessages.append(text)
                return PickupSnapshot(
                    pickupId: UUID(),
                    status: .arrived,
                    place: self.initialPlace,
                    placeVersion: 1,
                    participant: nil,
                    placeProposal: nil,
                    quickMessage: PickupSnapshot.QuickMessage(text: text),
                    vehicleName: "흰색 아이오닉 5"
                )
            },
            isSessionLost: { _ in false },
            onSessionLost: {},
            onTerminal: {},
            formatError: { _ in "error" },
            lostMessage: "lost"
        ))

        tracker.messageDraft = "입구 왼쪽이에요"
        await tracker.notifyArrivalBoarding()
        XCTAssertEqual(sentMessages, ["차량 확인했어요, 지금 탑승해요"])
        XCTAssertTrue(tracker.arrivalBoardingNotified)
        XCTAssertEqual(tracker.messageDraft, "입구 왼쪽이에요")
    }

    func testLiveActivityConnectionProblemClearsCountdownAndShowsLastCheckedText() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let activeSnapshot = makeSnapshot(status: .active, place: initialPlace, placeVersion: 1, ready: true)
        let previousState = try XCTUnwrap(PickupLiveActivityService.makeState(
            snapshot: activeSnapshot,
            vehicle: makeVehicle(durationSeconds: 180, validForMillis: 20_000),
            vehicleUpdatedAt: now,
            previousState: nil,
            now: now
        ))
        XCTAssertFalse(previousState.isReconnecting)
        XCTAssertEqual(previousState.reliabilityText(now: now.addingTimeInterval(5)), "마지막 확인 방금 전")

        let disconnectedAt = now.addingTimeInterval(65)
        let disconnectedState = try XCTUnwrap(PickupLiveActivityService.makeState(
            snapshot: activeSnapshot,
            vehicle: nil,
            vehicleUpdatedAt: nil,
            previousState: previousState,
            connectionProblem: true,
            lastCheckedAt: now,
            now: disconnectedAt
        ))
        XCTAssertTrue(disconnectedState.isReconnecting)
        XCTAssertNil(disconnectedState.estimatedArrivalDate)
        XCTAssertNil(disconnectedState.durationSeconds)
        XCTAssertNil(disconnectedState.vehicleFreshUntil)
        XCTAssertNil(disconnectedState.activeTimerRange(at: disconnectedAt))
        XCTAssertEqual(disconnectedState.reliabilityText(isStale: true, now: disconnectedAt), "연결 확인 중 · 마지막 확인 1분 전")
    }

    func testMinimizeAndReopenGuestPickupKeepsSessionActive() async {
        let activeSnapshot = makeSnapshot(status: .active, place: initialPlace, placeVersion: 1)
        let viewModel = PickupViewModel(
            transport: makeViewModelTransport(
                snapshot: { _ in activeSnapshot },
                vehicle: { _ in self.makeVehicle() }
            ),
            initialSession: nil
        )

        let inviteURL = "https://majung.cloud/#join/11111111-2222-4333-8444-555555555555/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm0123"
        await viewModel.openLink(inviteURL)
        await viewModel.join()
        XCTAssertEqual(viewModel.page, .pickup)
        XCTAssertNotNil(viewModel.session)

        viewModel.minimizePickup()
        XCTAssertEqual(viewModel.page, .entry)
        XCTAssertNotNil(viewModel.session)
        XCTAssertTrue(viewModel.hasActivePickupScreen)

        viewModel.reopenPickup()
        XCTAssertEqual(viewModel.page, .pickup)
        XCTAssertNotNil(viewModel.session)
    }

    func testTrackerEvaluatesSharedNotificationsWithoutOpenViewAndClearsOnCompletion() async {
        let suiteName = "MajungTests.TrackerNotifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "majung.arrivalAlertEnabled")

        var addedIdentifiers: [String] = []
        var removedIdentifierBatches: [[String]] = []
        let notifications = PickupNotificationService(
            defaults: defaults,
            addNotification: { request in
                addedIdentifiers.append(request.identifier)
            },
            removeNotifications: { identifiers in
                removedIdentifierBatches.append(identifiers)
            }
        )

        let tracker = PickupTracker(notifications: notifications)
        let pickupId = UUID()
        let activeSnap = PickupSnapshot(
            pickupId: pickupId,
            status: .active,
            place: initialPlace,
            placeVersion: 1,
            participant: PickupSnapshot.Participant(readiness: "NOT_READY", readinessSequence: 1, readinessReceivedSequence: 1),
            placeProposal: nil,
            quickMessage: nil,
            vehicleName: "흰색 아이오닉 5"
        )

        // Far away (> 3 minutes) should not alert
        tracker.applyExternal(activeSnap, vehicle: makeVehicle(durationSeconds: 360))
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(addedIdentifiers.isEmpty)

        // Approaching (<= 3 minutes) triggers approaching alert directly from tracker
        let pickupKey = pickupId.uuidString.lowercased()
        let approachingId = "majung.approaching-\(pickupKey)"
        let arrivedId = "majung.arrived-\(pickupKey)"

        tracker.applyExternal(activeSnap, vehicle: makeVehicle(durationSeconds: 150))
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(addedIdentifiers, [approachingId])

        // Arrived triggers arrival alert directly from tracker
        let arrivedSnap = PickupSnapshot(
            pickupId: pickupId,
            status: .arrived,
            place: initialPlace,
            placeVersion: 1,
            participant: nil,
            placeProposal: nil,
            quickMessage: nil,
            vehicleName: "흰색 아이오닉 5"
        )
        tracker.applyExternal(arrivedSnap, vehicle: nil)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(addedIdentifiers, [approachingId, arrivedId])

        // Terminal status clears previously delivered pickup notifications
        let completedSnap = PickupSnapshot(
            pickupId: pickupId,
            status: .completed,
            place: initialPlace,
            placeVersion: 1,
            participant: nil,
            placeProposal: nil,
            quickMessage: nil,
            vehicleName: "흰색 아이오닉 5"
        )
        tracker.applyExternal(completedSnap, vehicle: nil)
        let removedFlat = Set(removedIdentifierBatches.flatMap { $0 })
        XCTAssertTrue(removedFlat.contains(approachingId))
        XCTAssertTrue(removedFlat.contains(arrivedId))
    }

    func testLiveActivityCompactTimerFallsBackToMinutesLabelAtOneHourOrMore() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = makeSnapshot(status: .active, place: initialPlace, placeVersion: 1)

        // Under 1 hour: compact countdown range is active
        let underHour = try XCTUnwrap(PickupLiveActivityService.makeState(
            snapshot: snap,
            vehicle: makeVehicle(durationSeconds: 3540, validForMillis: 20_000),
            vehicleUpdatedAt: now,
            previousState: nil,
            now: now
        ))
        XCTAssertNotNil(underHour.activeTimerRange(at: now))
        XCTAssertNotNil(underHour.compactTimerRange(at: now))
        XCTAssertEqual(underHour.compactTrailingLabel, "59분")
        XCTAssertEqual(underHour.etaSummaryText, "약 59분 후 도착 예정")

        // 1 hour 10 minutes: expanded/lock screen still get full range, compact falls back to "70분" without ellipsis
        let overHour = try XCTUnwrap(PickupLiveActivityService.makeState(
            snapshot: snap,
            vehicle: makeVehicle(durationSeconds: 4200, validForMillis: 20_000),
            vehicleUpdatedAt: now,
            previousState: nil,
            now: now
        ))
        XCTAssertNotNil(overHour.activeTimerRange(at: now))
        XCTAssertNil(overHour.compactTimerRange(at: now))
        XCTAssertEqual(overHour.compactTrailingLabel, "70분")
        XCTAssertEqual(overHour.etaSummaryText, "약 1시간 10분 후 도착 예정")
    }

    func testNotificationForegroundBannerVisibilityAndTapDeepLinkRouting() {
        let suiteName = "MajungTests.NotificationRouting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = PickupNotificationService(defaults: defaults)
        let approachingId = "majung.approaching-11111111-2222-4333-8444-555555555555"

        // Away from pickup screen: show banner + list + sound
        service.isPickupScreenVisible = false
        let awayOptions = service.foregroundPresentationOptions(for: approachingId)
        XCTAssertTrue(awayOptions.contains(.banner))
        XCTAssertTrue(awayOptions.contains(.list))
        XCTAssertTrue(awayOptions.contains(.sound))

        // On pickup screen: sound only (no stale banner covering pickup UI)
        service.isPickupScreenVisible = true
        let visibleOptions = service.foregroundPresentationOptions(for: approachingId)
        XCTAssertFalse(visibleOptions.contains(.banner))
        XCTAssertTrue(visibleOptions.contains(.sound))

        // Debug/other notification still presents banner
        let debugOptions = service.foregroundPresentationOptions(for: "majung.debug.sample.123")
        XCTAssertTrue(debugOptions.contains(.banner))

        // Notification tap with explicit userInfo deep link
        service.handleNotificationTap(
            userInfo: ["pickupDeepLink": "majung://pickup/abc-123"],
            identifier: "custom"
        )
        XCTAssertEqual(service.consumePendingDeepLinkURL()?.absoluteString, "majung://pickup/abc-123")
        XCTAssertNil(service.consumePendingDeepLinkURL())

        // Notification tap fallback from identifier
        service.handleNotificationTap(userInfo: [:], identifier: approachingId)
        XCTAssertEqual(
            service.consumePendingDeepLinkURL()?.absoluteString,
            "majung://pickup/11111111-2222-4333-8444-555555555555"
        )
    }
}
