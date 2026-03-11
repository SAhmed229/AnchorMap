//
//  ScanDetailView.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 18/12/2025.
//

import SwiftUI
import SceneKit
import SwiftData
import CloudKit

struct ScanDetailView: View {
    let scan: ScanRecord
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var isPublishing = false
    @State private var publishError: String?
    @State private var showPublishError = false
    @AppStorage("uploaderName") private var uploaderName = "Anonymous"
    @State private var loadedScene: SCNScene?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let scene = loadedScene {
                    SceneViewWrapper(scene: scene)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if scan.fileURL != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("File Not Found", systemImage: "exclamationmark.triangle", description: Text("The scan file could not be loaded."))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(scan.name)
                            .font(.custom("Kosugi-Regular", size: 18))
                        if scan.isPublic {
                            Image(systemName: "globe")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                    }
                    HStack {
                        Image(systemName: "calendar")
                        Text(scan.date, style: .date)
                    }
                    .font(.custom("Kosugi-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "location")
                        Text(String(format: "%.4f, %.4f", scan.latitude, scan.longitude))
                    }
                    .font(.custom("Kosugi-Regular", size: 14))
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
            }
            .navigationTitle(scan.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        if let url = scan.fileURL {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }

                        Button {
                            togglePublish()
                        } label: {
                            if isPublishing {
                                ProgressView()
                            } else {
                                Image(systemName: scan.isPublic ? "globe.badge.chevron.backward" : "globe")
                                    .foregroundStyle(scan.isPublic ? .blue : .primary)
                            }
                        }
                        .disabled(isPublishing)

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("Kosugi-Regular", size: 16))
                }
            }
            .alert("Delete Scan", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if scan.isPublic {
                        Task {
                            try? await CloudKitManager.shared.unpublishScan(scan)
                        }
                    }
                    scan.deleteFiles()
                    modelContext.delete(scan)
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(scan.name)\"? This cannot be undone.")
            }
            .alert("Publish Error", isPresented: $showPublishError) {
                Button("OK") {}
            } message: {
                Text(publishError ?? "Unknown error")
            }
            .task {
                guard let url = scan.fileURL,
                      FileManager.default.fileExists(atPath: url.path) else { return }
                let scene = await Task.detached(priority: .userInitiated) {
                    let s = (try? SCNScene(url: url)) ?? SCNScene()
                    s.rootNode.enableVertexColors()
                    return s
                }.value
                loadedScene = scene
            }
        }
    }

    private func togglePublish() {
        isPublishing = true
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
                publishError = CloudKitManager.userMessage(for: error)
                showPublishError = true
            }
            isPublishing = false
        }
    }

}
