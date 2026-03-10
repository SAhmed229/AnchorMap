//
//  FetchModelView.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 02/02/2026.
//

import SwiftUI
import SceneKit
import SwiftData
import CloudKit

struct FetchModelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.date, order: .reverse) private var scans: [ScanRecord]
    @State private var selectedScan: ScanRecord?

    var body: some View {
        NavigationStack {
            List {
                ForEach(scans) { scan in
                    Button {
                        selectedScan = scan
                    } label: {
                        HStack {
                            if let data = scan.thumbnailData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .cornerRadius(6)
                            } else {
                                Image(systemName: "cube")
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(6)
                            }
                            VStack(alignment: .leading) {
                                HStack(spacing: 4) {
                                    Text(scan.name)
                                        .font(.custom("Kosugi-Regular", size: 16))
                                    if scan.isPublic {
                                        Image(systemName: "globe")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text(scan.date, style: .date)
                                    .font(.custom("Kosugi-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "eye.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteScan(scan)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            togglePublish(scan)
                        } label: {
                            Label(scan.isPublic ? "Unpublish" : "Publish",
                                  systemImage: scan.isPublic ? "globe.badge.chevron.backward" : "globe")
                        }
                        .tint(.blue)
                    }
                }
            }
            .navigationTitle("Library")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Library")
                        .font(.custom("Kosugi-Regular", size: 18))
                }
            }
            .sheet(item: $selectedScan) { scan in
                ScanDetailView(scan: scan)
            }
            .overlay {
                if scans.isEmpty {
                    ContentUnavailableView {
                        Label("No Scans Yet", systemImage: "viewfinder")
                    } description: {
                        Text("Export a LiDAR scan to see it here.")
                            .font(.custom("Kosugi-Regular", size: 14))
                    }
                }
            }
        }
    }

    private func deleteScan(_ scan: ScanRecord) {
        if scan.isPublic {
            Task {
                try? await CloudKitManager.shared.unpublishScan(scan)
            }
        }
        scan.deleteFiles()
        modelContext.delete(scan)
    }

    private func togglePublish(_ scan: ScanRecord) {
        Task {
            do {
                if scan.isPublic {
                    try await CloudKitManager.shared.unpublishScan(scan)
                    scan.isPublic = false
                    scan.cloudKitRecordID = nil
                } else {
                    let recordID = try await CloudKitManager.shared.publishScan(scan)
                    scan.cloudKitRecordID = recordID.recordName
                    scan.isPublic = true
                }
                try? modelContext.save()
            } catch {
                print("[Library] Publish toggle failed: \(error)")
            }
        }
    }
}

struct SceneViewWrapper: UIViewRepresentable {
    let scene: SCNScene?
    func makeUIView(context: Context) -> some UIView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.antialiasingMode = .multisampling2X
        scnView.scene = scene
        scnView.backgroundColor = .clear
        return scnView
    }
    func updateUIView(_ uiView: UIViewType, context: Context) { }
}
