import SwiftUI
import UIKit

struct MainTabView: View {
    @Bindable var account: AccountViewModel
    @Bindable var people: PeopleViewModel
    @Bindable var rideRequests: RideRequestViewModel
    @Bindable var vehicleLinks: VehicleLinkViewModel
    @Bindable var pickup: PickupViewModel
    @Binding var inviteLink: String
    var pickupNavigationEventCount = 0

    @State private var selectedTab: TabItem = .home
    @State private var rideTarget: RideTargetPerson?
    @State private var showingRideTracking = false
    @State private var pendingPickupDeepLink = false

    private enum TabItem: Hashable {
        case home, requests, people, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeTabView(
                    account: account,
                    rideRequests: rideRequests,
                    pickup: pickup,
                    inviteLink: $inviteLink,
                    onOpenRequests: { selectedTab = .requests },
                    onOpenPeople: { selectedTab = .people },
                    onOpenTracking: {
                        rideRequests.beginTrackingSession()
                        showingRideTracking = true
                    }
                )
            }
            .tabItem {
                Label("홈", systemImage: "house.fill")
            }
            .tag(TabItem.home)

            NavigationStack {
                RequestsTabView(
                    rideModel: rideRequests,
                    onOpenPeople: { selectedTab = .people },
                    onOpenTracking: {
                        rideRequests.beginTrackingSession()
                        showingRideTracking = true
                    }
                )
            }
            .tabItem {
                Label("내 요청·초대", systemImage: "clock.fill")
            }
            .badge(rideRequests.invitedCount)
            .tag(TabItem.requests)

            NavigationStack {
                PeopleTabView(account: account, people: people) { target in
                    rideRequests.error = nil
                    rideTarget = target
                }
            }
            .tabItem {
                Label("사람", systemImage: "person.2.fill")
            }
            .tag(TabItem.people)

            NavigationStack {
                SettingsTabView(
                    account: account,
                    people: people,
                    rideRequests: rideRequests,
                    vehicleLinks: vehicleLinks
                )
            }
            .tabItem {
                Label("설정", systemImage: "gearshape.fill")
            }
            .tag(TabItem.settings)
        }
        .sheet(item: $rideTarget) { target in
            PlacePickerSheet(target: target, rideModel: rideRequests) {
                selectedTab = .requests
            }
        }
        .sheet(isPresented: $showingRideTracking) {
            NavigationStack {
                PickupView(tracker: rideRequests.tracking, resetLabel: "목록으로") {
                    showingRideTracking = false
                    rideRequests.clearEndedTrackingIfNeeded()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") {
                            showingRideTracking = false
                            rideRequests.clearEndedTrackingIfNeeded()
                        }
                    }
                }
            }
        }
        .onChange(of: rideRequests.activeRequest?.id) { _, activeId in
            if activeId != nil && pendingPickupDeepLink {
                pendingPickupDeepLink = false
                rideRequests.beginTrackingSession()
                showingRideTracking = true
            }
            if activeId == nil && !showingRideTracking {
                rideRequests.clearEndedTrackingIfNeeded()
            }
            if activeId == nil && rideRequests.tracking.snapshot == nil {
                showingRideTracking = false
            }
        }
        .onChange(of: showingRideTracking) { _, isShowing in
            if !isShowing {
                rideRequests.clearEndedTrackingIfNeeded()
            }
        }
        .onChange(of: selectedTab) { _, _ in
            dismissMajungKeyboard()
        }
        .onChange(of: vehicleLinks.navigationEventCount) { _, count in
            if count > 0 { selectedTab = .settings }
        }
        .onChange(of: pickupNavigationEventCount) { _, count in
            guard count > 0 else { return }
            openActivePickupFromDeepLink()
        }
        .onAppear {
            if vehicleLinks.hasPendingPairing || vehicleLinks.navigationEventCount > 0 {
                selectedTab = .settings
            }
            if pickupNavigationEventCount > 0 {
                openActivePickupFromDeepLink()
            }
        }
    }

    private func openActivePickupFromDeepLink() {
        if rideRequests.activeRequest != nil {
            pendingPickupDeepLink = false
            rideRequests.beginTrackingSession()
            showingRideTracking = true
        } else {
            pendingPickupDeepLink = true
            selectedTab = .requests
        }
    }
}
