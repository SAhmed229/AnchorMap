//
//  PublicScan.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 02/11/2025.
//

import Foundation
import CloudKit
import CoreLocation

struct PublicScan: Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let date: Date
    let uploaderName: String
    let recordID: CKRecord.ID

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(record: CKRecord) {
        self.id = record.recordID.recordName
        self.name = record["name"] as? String ?? "Unnamed Scan"
        self.latitude = record["latitude"] as? Double ?? 0
        self.longitude = record["longitude"] as? Double ?? 0
        self.date = record["date"] as? Date ?? Date()
        self.uploaderName = record["uploaderName"] as? String ?? "Unknown"
        self.recordID = record.recordID
    }
}
