//
//  ExploreView.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 05/01/2026.
//

import SwiftUI
import MapKit
import SceneKit

struct ExploreView: View {
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var publicScans: [PublicScan] = []
    @State private var selectedScan: PublicScan?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var downloadingScanID: String?
    @State private var downloadedSceneURL: URL?
    @State private var showSceneViewer = false
    @State private var mapRegion = MKCoordinateRegion()
    @State private var fetchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    ForEach(publicScans) { scan in
                        Annotation(scan.name, coordinate: scan.coordinate) {
                            Button {
                                selectedScan = scan
                            } label: {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    mapRegion = context.region
                    debouncedFetch()
                }

                if isLoading && publicScans.isEmpty {
                    ProgressView("Loading public scans...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Explore")
                        .font(.custom("Kosugi-Regular", size: 18))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        fetchPublicScans()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $selectedScan) { scan in
                PublicScanDetailSheet(scan: scan, downloadingScanID: $downloadingScanID) {
                    downloadAndView(scan)
                }
            }
            .sheet(isPresented: $showSceneViewer) {
                if let url = downloadedSceneURL {
                    NavigationStack {
                        SceneViewWrapper(scene: loadScene(from: url))
                            .navigationTitle("Viewer")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { showSceneViewer = false }
                                        .font(.custom("Kosugi-Regular", size: 16))
                                }
                            }
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }

            .overlay {
                if !isLoading && publicScans.isEmpty {
                    ContentUnavailableView("No Public Scans Yet",
                        systemImage: "map",
                        description: Text("Scans published nearby will appear here."))
                }
            }
        }
    }

    private func debouncedFetch() {
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            fetchPublicScans()
        }
    }

    private func fetchPublicScans() {
        let center = mapRegion.center
        guard center.latitude != 0 && center.longitude != 0 else { return }

        let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let radiusKm = max(mapRegion.span.latitudeDelta * 111, 5)

        isLoading = true
        Task {
            do {
                publicScans = try await CloudKitManager.shared.fetchPublicScans(near: location, radiusKm: radiusKm)
            } catch {
                errorMessage = CloudKitManager.userMessage(for: error)
                showError = true
            }
            isLoading = false
        }
    }

    private func downloadAndView(_ scan: PublicScan) {
        downloadingScanID = scan.id
        Task {
            do {
                let url = try await CloudKitManager.shared.downloadScanFile(from: scan)
                downloadedSceneURL = url
                selectedScan = nil
                showSceneViewer = true
            } catch {
                errorMessage = CloudKitManager.userMessage(for: error)
                showError = true
            }
            downloadingScanID = nil
        }
    }

    private func loadScene(from url: URL) -> SCNScene {
        let scene = (try? SCNScene(url: url)) ?? SCNScene()
        scene.rootNode.enableVertexColors()
        return scene
    }
}

struct PublicScanDetailSheet: View {
    let scan: PublicScan
    @Binding var downloadingScanID: String?
    let onView: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(scan.name)
                .font(.custom("Kosugi-Regular", size: 20))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person")
                    Text(scan.uploaderName)
                }
                HStack {
                    Image(systemName: "calendar")
                    Text(scan.date, style: .date)
                }
                HStack {
                    Image(systemName: "location")
                    Text(String(format: "%.4f, %.4f", scan.latitude, scan.longitude))
                }
            }
            .font(.custom("Kosugi-Regular", size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onView()
            } label: {
                if downloadingScanID == scan.id {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("View Scan")
                        .font(.custom("Kosugi-Regular", size: 16))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.18, green: 0.55, blue: 0.48))
            .disabled(downloadingScanID != nil)
        }
        .padding(24)
        .presentationDetents([.height(280)])
    }
}
