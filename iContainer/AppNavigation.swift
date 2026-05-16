import AppKit
import Combine
import SwiftUI

@MainActor
final class AppNavigation: ObservableObject {
    @Published var containerTarget: ContainerNavigationTarget?
    @Published var editContainerId: String?
    @Published var serviceRequestID = 0

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

    func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
