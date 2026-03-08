//
//  ContentView.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 18/10/2025.
//

import SwiftUI
import ARKit
import RealityKit
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var scanState: ScanState = .idle
    @State private var exportTrigger = false
    @State private var exportedURL: URL?
    @State private var showNameSheet = false
    @State private var scanName = ""
    @State private var pendingExport = false
    @State private var arManager = ARManager()

    private let mapColor = Color(red: 0.18, green: 0.55, blue: 0.48)

    var body: some View {
        ZStack {
            ARWrapper(scanState: $scanState, exportTrigger: $exportTrigger, exportedUrl: $exportedURL)
                .ignoresSafeArea()

            VStack {
                Spacer()

                Group {
                    switch scanState {
                    case .idle:
                        Button { scanState = .scanning } label: {
                            scanButton("Start Scanning")
                        }

                    case .scanning:
                        Button { scanState = .paused } label: {
                            scanButton("Pause")
                        }

                    case .paused:
                        HStack(spacing: 16) {
                            Button {
                                scanState = .idle
                            } label: {
                                scanButton("Discard")
                            }

                            Button {
                                scanState = .scanning
                            } label: {
                                scanButton("Resume")
                            }

                            Button {
                                showNameSheet = true
                            } label: {
                                scanButton("Export")
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            arManager.requestLocation()
        }
        .sheet(isPresented: $showNameSheet, onDismiss: {
            // Fire export AFTER sheet is fully dismissed
            if pendingExport {
                pendingExport = false
                exportTrigger = true
                print("[ContentView] Export triggered after sheet dismiss")
            } else {
                scanName = ""
            }
        }) {
            SaveScanSheet(scanName: $scanName) {
                // Mark for export, then dismiss
                pendingExport = true
                showNameSheet = false
            } onDiscard: {
                showNameSheet = false
            }
            .presentationDetents([.height(220)])
            .interactiveDismissDisabled()
        }
        .onChange(of: exportedURL) { _, newURL in
            guard let newURL else { return }
            print("[ContentView] Export complete: \(newURL.lastPathComponent)")
            saveScanRecord(url: newURL)
            scanState = .idle
        }
    }

    @ViewBuilder
    private func scanButton(_ title: String) -> some View {
        Text(title)
            .font(.custom("Kosugi-Regular", size: 16))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(mapColor)
            .cornerRadius(12)
    }

    private func saveScanRecord(url: URL) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let relativePath = url.path.replacingOccurrences(of: docs.path + "/", with: "")

        let lat = arManager.lastKnownLocation?.latitude ?? 0
        let lon = arManager.lastKnownLocation?.longitude ?? 0
        let name = scanName.trimmingCharacters(in: .whitespaces)

        let record = ScanRecord(
            name: name.isEmpty ? url.deletingPathExtension().lastPathComponent : name,
            latitude: lat,
            longitude: lon,
            filePath: relativePath
        )
        modelContext.insert(record)
        try? modelContext.save()
        print("[ContentView] ScanRecord saved: \(record.name) at \(lat),\(lon) -> \(relativePath)")
        scanName = ""
    }
}

// MARK: - Save/Discard Sheet

struct SaveScanSheet: View {
    @Binding var scanName: String
    var onSave: () -> Void
    var onDiscard: () -> Void

    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        scanName.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Save Scan")
                .font(.custom("Kosugi-Regular", size: 20))

            TextField("Enter scan name", text: $scanName)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { isFocused = true }
                .submitLabel(.done)
                .onSubmit {
                    if !trimmedName.isEmpty { onSave() }
                }

            HStack(spacing: 16) {
                Button(role: .cancel) {
                    onDiscard()
                } label: {
                    Text("Cancel")
                        .font(.custom("Kosugi-Regular", size: 16))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onSave()
                } label: {
                    Text("Save")
                        .font(.custom("Kosugi-Regular", size: 16))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.18, green: 0.55, blue: 0.48))
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
    }
}
