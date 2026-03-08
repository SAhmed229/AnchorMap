//
//  MapView.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 04/03/2026.
//

import SwiftUI
import MapKit
import SwiftData
import CoreLocation

struct MapView: View {
    @Query(sort: \ScanRecord.date, order: .reverse) private var scans: [ScanRecord]
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedScan: ScanRecord?
    @State private var showPublicScans = false
    @State private var publicScans: [PublicScan] = []
    @State private var mapRegion = MKCoordinateRegion()
    @State private var fetchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(scans) { scan in
                    Annotation(scan.name, coordinate: scan.coordinate) {
                        Button {
                            selectedScan = scan
                        } label: {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                        }
                    }
                }
                if showPublicScans {
                    ForEach(publicScans) { scan in
                        Annotation(scan.name, coordinate: scan.coordinate) {
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
                if showPublicScans {
                    debouncedFetchPublicScans()
                }
            }
            .navigationTitle("AnchorMap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("AnchorMap")
                        .font(.custom("Kosugi-Regular", size: 18))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPublicScans.toggle()
                        if showPublicScans {
                            debouncedFetchPublicScans()
                        } else {
                            publicScans = []
                        }
                    } label: {
                        Image(systemName: showPublicScans ? "globe.americas.fill" : "globe.americas")
                            .foregroundStyle(showPublicScans ? .blue : .primary)
                    }
                }
            }
            .sheet(item: $selectedScan) { scan in
                ScanDetailView(scan: scan)
            }
        }
    }

    private func debouncedFetchPublicScans() {
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let center = mapRegion.center
            guard center.latitude != 0 && center.longitude != 0 else { return }

            let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let radiusKm = max(mapRegion.span.latitudeDelta * 111, 5)

            do {
                publicScans = try await CloudKitManager.shared.fetchPublicScans(near: location, radiusKm: radiusKm)
            } catch {
                print("[MapView] Failed to fetch public scans: \(error)")
            }
        }
    }
}
