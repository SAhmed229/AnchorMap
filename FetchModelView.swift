//
//  FetchModelView.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 03/11/2026.
//

import SwiftUI
import SceneKit
import SwiftData
import CloudKit

struct FetchModelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.date, order: .reverse) private var scans: [ScanRecord]
    @State private var selectedScan: ScanRecord?
    @AppStorage("uploaderName") private var uploaderName = "Anonymous"
    @State private var showNameEditor = false
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(scans) { scan in
                    Button {
                        selectedScan = scan
                    } label: {
                        HStack {
                            ThumbnailView(data: scan.thumbnailData)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftName = uploaderName
                        showNameEditor = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .sheet(isPresented: $showNameEditor) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Text("This name will appear when you publish scans.")
                            .font(.custom("Kosugi-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        TextField("Enter your name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .font(.custom("Kosugi-Regular", size: 16))

                        Button("Stay Anonymous") {
                            uploaderName = "Anonymous"
                            showNameEditor = false
                        }
                        .font(.custom("Kosugi-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .navigationTitle("Display Name")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showNameEditor = false }
                                .font(.custom("Kosugi-Regular", size: 16))
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") {
                                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                                uploaderName = trimmed.isEmpty ? "Anonymous" : trimmed
                                showNameEditor = false
                            }
                            .font(.custom("Kosugi-Regular", size: 16))
                        }
                    }
                }
                .presentationDetents([.height(250)])
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
                    let recordID = try await CloudKitManager.shared.publishScan(scan, uploaderName: uploaderName)
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

private struct ThumbnailView: View {
    let data: Data?
    @State private var image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .frame(width: 50, height: 50)
                .cornerRadius(6)
        } else {
            Image(systemName: "cube")
                .frame(width: 50, height: 50)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(6)
                .task {
                    guard let data else { return }
                    let decoded = await Task.detached(priority: .utility) {
                        UIImage(data: data)
                    }.value
                    image = decoded
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

