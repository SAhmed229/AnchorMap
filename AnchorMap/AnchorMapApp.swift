//
//  AnchorMapApp.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 18/10/2025.
//

import SwiftUI
import SwiftData

@main
struct AnchorMapApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                MapView()
                    .tabItem {
                        Label("Map", systemImage: "map")
                    }

                ContentView()
                    .tabItem {
                        Label("Scan", systemImage: "camera.viewfinder")
                    }

                ExploreView()
                    .tabItem {
                        Label("Explore", systemImage: "globe")
                    }

                FetchModelView()
                    .tabItem {
                        Label("Library", systemImage: "list.bullet")
                    }
            }
        }
        .modelContainer(for: ScanRecord.self)
    }
}
