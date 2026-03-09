//
//  iContainerApp.swift
//  iContainer
//
//  Created by Nico Emanuelli on 11/07/25.
//

import SwiftUI

@main
struct iContainerApp: App {
    @StateObject private var containerManager = ContainerizationWrapper()
    @StateObject private var serviceManager = ServiceManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(containerManager)
                .environmentObject(serviceManager)
        }
    }
}
