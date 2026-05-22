//
//  iContainerApp.swift
//  iContainer
//
//  Created by Nico Emanuelli on 11/07/25.
//

import SwiftUI

@main
struct iContainerApp: App {
    @NSApplicationDelegateAdaptor(AppQuitDelegate.self) private var appQuitDelegate
    @StateObject private var containerManager = ContainerizationWrapper()
    @StateObject private var serviceManager = ServiceManager()
    @StateObject private var appNavigation = AppNavigation()
    @StateObject private var releaseChecker = ContainerReleaseChecker()

    var body: some Scene {
        Window("iContainer", id: "main") {
            ContentView()
                .environmentObject(containerManager)
                .environmentObject(serviceManager)
                .environmentObject(appNavigation)
                .environmentObject(releaseChecker)
                .onAppear {
                    appQuitDelegate.serviceManager = serviceManager
                }
        }

        MenuBarExtra {
            MenuBarContainersView()
                .environmentObject(containerManager)
                .environmentObject(serviceManager)
                .environmentObject(appNavigation)
        } label: {
            Image(menuBarIconName)
                .renderingMode(.template)
                .id(serviceManager.isServiceRunning)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIconName: String {
        serviceManager.isServiceRunning ? "MenuBarIcon" : "MenuBarIconInactive"
    }
}
