//
//  ScanRecord.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 04/03/2026.
//

import Foundation
import SwiftData
import CoreLocation

@Model
class ScanRecord {
    var id: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var filePath: String = ""
    var date: Date = Date.now
    var isPublic: Bool = false
    var cloudKitRecordID: String?
    @Attribute(.externalStorage) var thumbnailData: Data?

    init(name: String, latitude: Double, longitude: Double, filePath: String, date: Date = .now, thumbnailData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.filePath = filePath
        self.date = date
        self.thumbnailData = thumbnailData
    }

    var fileURL: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent(filePath)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func deleteFiles() {
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
