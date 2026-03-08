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

    var lastKnownLocation: CLLocationCoordinate2D?

    override init()
    {
        super.init()
        locationManager.delegate = self
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

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastKnownLocation = location.coordinate
        currentUserLocation.send(location.coordinate)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
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
