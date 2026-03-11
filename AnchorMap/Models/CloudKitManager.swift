//
//  CloudKitManager.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 02/11/2026.
//

import Foundation
import CloudKit
import CoreLocation

@Observable
class CloudKitManager {
    static let shared = CloudKitManager()

    private let container = CKContainer(identifier: "iCloud.com.ahmedshousha.AnchorMap")
    private var publicDatabase: CKDatabase { container.publicCloudDatabase }

    var isUploading = false
    var uploadError: String?

    private var fetchCache: (key: String, scans: [PublicScan], date: Date)?

    private init() {}

    // MARK: - Publish

    func publishScan(_ record: ScanRecord, uploaderName: String) async throws -> CKRecord.ID {
        guard let fileURL = record.fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CloudKitError.fileNotFound
        }

        let ckRecord = CKRecord(recordType: "PublicScan")
        ckRecord["name"] = record.name as CKRecordValue
        ckRecord["latitude"] = record.latitude as CKRecordValue
        ckRecord["longitude"] = record.longitude as CKRecordValue
        ckRecord["location"] = CLLocation(latitude: record.latitude, longitude: record.longitude) as CKRecordValue
        ckRecord["date"] = record.date as CKRecordValue
        ckRecord["uploaderName"] = uploaderName as CKRecordValue
        ckRecord["scanFile"] = CKAsset(fileURL: fileURL)

        if let thumbnailData = record.thumbnailData {
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            try thumbnailData.write(to: tmpURL)
            ckRecord["thumbnail"] = CKAsset(fileURL: tmpURL)
        }

        let savedRecord = try await publicDatabase.save(ckRecord)
        return savedRecord.recordID
    }

    // MARK: - Unpublish

    func unpublishScan(_ record: ScanRecord) async throws {
        guard let recordIDName = record.cloudKitRecordID else {
            throw CloudKitError.noRecordID
        }
        let recordID = CKRecord.ID(recordName: recordIDName)
        try await publicDatabase.deleteRecord(withID: recordID)
    }

    // MARK: - Fetch Public Scans

    func fetchPublicScans(near location: CLLocation, radiusKm: Double) async throws -> [PublicScan] {
        let cacheKey = String(format: "%.2f,%.2f,%.0f",
                              location.coordinate.latitude,
                              location.coordinate.longitude,
                              radiusKm)
        if let cache = fetchCache, cache.key == cacheKey,
           Date().timeIntervalSince(cache.date) < 60 {
            return cache.scans
        }

        let radiusMeters = radiusKm * 1000
        let predicate = NSPredicate(
            format: "distanceToLocation:fromLocation:(location, %@) < %f",
            location, radiusMeters
        )
        let query = CKQuery(recordType: "PublicScan", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        do {
            let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 50)

            let scans: [PublicScan] = results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return PublicScan(record: record)
            }
            fetchCache = (cacheKey, scans, Date())
            return scans
        } catch let error as CKError where error.code == .unknownItem {
            return []  // Record type not yet created — not an error
        }
    }

    // MARK: - Download Scan File

    func downloadScanFile(from publicScan: PublicScan) async throws -> URL {
        let record = try await publicDatabase.record(for: publicScan.recordID)

        guard let asset = record["scanFile"] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw CloudKitError.assetNotFound
        }

        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(publicScan.id).scn")

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: assetURL, to: destURL)

        return destURL
    }

    // MARK: - Error Handling

    static func userMessage(for error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                return "No internet connection. Please try again later."
            case .quotaExceeded:
                return "iCloud storage is full. Free up space and try again."
            case .notAuthenticated:
                return "Please sign in to iCloud in Settings."
            case .permissionFailure:
                return "iCloud permission denied. Check Settings > iCloud."
            default:
                return "CloudKit error: \(ckError.localizedDescription)"
            }
        }
        if let cloudKitError = error as? CloudKitError {
            return cloudKitError.message
        }
        return error.localizedDescription
    }
}

enum CloudKitError: Error {
    case fileNotFound
    case noRecordID
    case assetNotFound

    var message: String {
        switch self {
        case .fileNotFound: return "Scan file not found on device."
        case .noRecordID: return "This scan has no CloudKit record to unpublish."
        case .assetNotFound: return "Could not download the scan file."
        }
    }
}
