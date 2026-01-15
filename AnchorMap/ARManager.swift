//
//  ARManager.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 15/11/2025.
//
import ARKit
import SwiftUI
import RealityKit
import Combine
import CoreLocation


@Observable class ARManager: NSObject, CLLocationManagerDelegate
{
    let session = ARSession()
    let worldConfig = ARWorldTrackingConfiguration()
    let geoConfig = ARGeoTrackingConfiguration()
    let locationManager = CLLocationManager()
    let currentUserLocation = PassthroughSubject<CLLocationCoordinate2D, Never>()
    private var cancellables = Set<AnyCancellable>()
    override init()
    {
        super.init()
        locationManager.delegate = self
    }
    func startLidarScan()
    {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        {
            worldConfig.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            worldConfig.frameSemantics.insert(.sceneDepth)
        }
        session.run(worldConfig)
    }
    func startGeoTracking()
    {
        session.run(geoConfig)
    }
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation])
    {

        if let newest = locations.last
        {
            let coordinate = newest.coordinate
            currentUserLocation.send(coordinate)
            
        }
    }

    func requestLocation()
    {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .restricted, .denied:
            break
        @unknown default:
            break
        }
    }
    func geotagScan(withName name: String)
    {
        currentUserLocation
            .sink { coordinate in
                let anchor = ARGeoAnchor(name: name, coordinate: coordinate)
                self.session.add(anchor: anchor)
            }
            .store(in: &cancellables)
    }
}
