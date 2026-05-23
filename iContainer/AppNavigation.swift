import AppKit
import Combine
import SwiftUI

/// Commands the user can invoke against the container currently selected
/// in the sidebar. Sent by menu items / keyboard shortcuts and consumed by
/// `ContentView`, which knows how to resolve them against the live
/// selection and container state.
enum ContainerCommand: Equatable {
    case start
    case stop
    case restart
    case showTab(Int)
    case edit
    case delete
}

/// One-shot request for a `ContainerCommand`. The `id` is a monotonically
/// increasing token so observers can react via `onChange` / `onReceive`
/// even when the same command is fired twice in a row.
struct ContainerCommandRequest: Equatable {
    let command: ContainerCommand
    let id: Int
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var containerTarget: ContainerNavigationTarget?
    @Published var editContainerId: String?
    @Published var serviceRequestID = 0

    // Intents fired by menu items / keyboard shortcuts in the App scene.
    // Each property is a monotonically increasing counter so `ContentView`
    // can react to repeated triggers via `onReceive`.
    @Published var newContainerRequestID = 0
    @Published var pullImageRequestID = 0
    @Published var registryLoginRequestID = 0
    @Published var refreshRequestID = 0
    @Published var overviewRequestID = 0
    @Published var settingsRequestID = 0
    @Published var containerCommandRequest: ContainerCommandRequest?

    /// Mirror of the sidebar selection. The selection state itself lives in
    /// `ContentView`, but the App-scope command menu needs to know the
    /// currently-selected container in order to enable/disable items and
    /// look up the container status.
    @Published var selectedContainerID: String?

    private var containerCommandCounter = 0

    func showContainer(id: String, tab: Int) {
        containerTarget = ContainerNavigationTarget(id: id, tab: tab)
        activateApp()
    }

    func editContainer(id: String) {
        editContainerId = id
        activateApp()
    }

    func showService() {
        serviceRequestID += 1
        activateApp()
    }

    func requestNewContainer() {
        newContainerRequestID &+= 1
        activateApp()
    }

    func requestPullImage() {
        pullImageRequestID &+= 1
        activateApp()
    }

    func requestRegistryLogin() {
        registryLoginRequestID &+= 1
        activateApp()
    }

    func requestRefresh() {
        refreshRequestID &+= 1
    }

    func requestOverview() {
        overviewRequestID &+= 1
        activateApp()
    }

    func requestSettings() {
        settingsRequestID &+= 1
        activateApp()
    }

    func requestContainerCommand(_ command: ContainerCommand) {
        containerCommandCounter &+= 1
        containerCommandRequest = ContainerCommandRequest(command: command, id: containerCommandCounter)
    }

    func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
