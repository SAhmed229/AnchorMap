//
//  ARWrapper.swift
//  AnchorMap
//
//  Created by Ahmed Shousha on 26/01/2026.
//

import SwiftUI
import RealityKit
import ARKit
import Combine
import Metal
import CoreImage
import SceneKit

enum ScanState: Equatable {
    case idle
    case scanning
    case paused
}

struct CameraKeyframe {
    let jpegData: Data
    let imageWidth: Int
    let imageHeight: Int
    let viewMatrix: simd_float4x4
    let projectionMatrix: simd_float4x4
    let position: simd_float3
}

// MARK: - CVPixelBuffer deep copy (memcpy, <1ms — releases ARFrame immediately)

extension CVPixelBuffer {
    func deepCopy() -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let format = CVPixelBufferGetPixelFormatType(self)
        let attachments = CVBufferCopyAttachments(self, .shouldPropagate)

        var copyOut: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, format, attachments, &copyOut)
        guard let copy = copyOut else { return nil }

        CVPixelBufferLockBaseAddress(self, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
        }

        let planeCount = CVPixelBufferGetPlaneCount(self)
        if planeCount > 0 {
            // Bi-planar (YCbCr 4:2:0)
            for plane in 0..<planeCount {
                let srcPtr = CVPixelBufferGetBaseAddressOfPlane(self, plane)!
                let dstPtr = CVPixelBufferGetBaseAddressOfPlane(copy, plane)!
                let h = CVPixelBufferGetHeightOfPlane(self, plane)
                let srcBPR = CVPixelBufferGetBytesPerRowOfPlane(self, plane)
                let dstBPR = CVPixelBufferGetBytesPerRowOfPlane(copy, plane)
                let rowBytes = min(srcBPR, dstBPR)
                for row in 0..<h {
                    memcpy(dstPtr.advanced(by: row * dstBPR),
                           srcPtr.advanced(by: row * srcBPR),
                           rowBytes)
                }
            }
        } else {
            let src = CVPixelBufferGetBaseAddress(self)!
            let dst = CVPixelBufferGetBaseAddress(copy)!
            memcpy(dst, src, CVPixelBufferGetDataSize(self))
        }
        return copy
    }
}

struct ARWrapper: UIViewRepresentable {
    @Binding var scanState: ScanState
    @Binding var exportTrigger: Bool
    @Binding var exportedUrl: URL?

    class Coordinator: NSObject, ARSessionDelegate {
        var currentState: ScanState = .idle
        var isExporting = false
        let exportViewModel = ExportViewModel()

        var keyframes: [CameraKeyframe] = []
        var lastKeyframePosition: simd_float3?
        var lastKeyframeTime: TimeInterval = 0
        var isCapturingKeyframe = false

        private let ciContext = CIContext()
        private static let maxKeyframes = 50
        private static let minDistance: Float = 0.10
        private static let minInterval: TimeInterval = 0.3

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard currentState == .scanning, !isCapturingKeyframe else { return }

            let camera = frame.camera
            let transform = camera.transform
            let position = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let timestamp = frame.timestamp

            // Check distance and time thresholds
            if let lastPos = lastKeyframePosition {
                let dist = simd_distance(position, lastPos)
                guard dist > Self.minDistance && (timestamp - lastKeyframeTime) > Self.minInterval else { return }
            }

            // Deep-copy pixel buffer synchronously (<1ms memcpy) so ARFrame is released immediately
            guard let bufferCopy = frame.capturedImage.deepCopy() else { return }

            // Mark capturing and update tracking state
            isCapturingKeyframe = true
            lastKeyframePosition = position
            lastKeyframeTime = timestamp

            let imgWidth = CVPixelBufferGetWidth(bufferCopy)
            let imgHeight = CVPixelBufferGetHeight(bufferCopy)
            let viewMatrix = camera.viewMatrix(for: .landscapeRight)
            let projectionMatrix = camera.projectionMatrix(
                for: .landscapeRight,
                viewportSize: CGSize(width: imgWidth, height: imgHeight),
                zNear: 0.001, zFar: 1000
            )

            // JPEG-compress the COPY on background (original ARFrame pixel buffer already freed)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                let ciImage = CIImage(cvPixelBuffer: bufferCopy)
                guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent),
                      let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) else {
                    DispatchQueue.main.async { self.isCapturingKeyframe = false }
                    return
                }

                let keyframe = CameraKeyframe(
                    jpegData: jpegData,
                    imageWidth: imgWidth,
                    imageHeight: imgHeight,
                    viewMatrix: viewMatrix,
                    projectionMatrix: projectionMatrix,
                    position: position
                )

                // Eviction logic on background thread to avoid blocking main thread
                if self.keyframes.count < Self.maxKeyframes {
                    self.keyframes.append(keyframe)
                } else {
                    // Evict the keyframe with the smallest nearest-neighbor distance
                    var minNearestDist: Float = .greatestFiniteMagnitude
                    var evictIndex = 0
                    for i in 0..<self.keyframes.count {
                        var nearestDist: Float = .greatestFiniteMagnitude
                        for j in 0..<self.keyframes.count where j != i {
                            nearestDist = min(nearestDist, simd_distance(self.keyframes[i].position, self.keyframes[j].position))
                        }
                        if nearestDist < minNearestDist {
                            minNearestDist = nearestDist
                            evictIndex = i
                        }
                    }
                    self.keyframes[evictIndex] = keyframe
                }

                print("[Keyframe] Captured \(self.keyframes.count) keyframes")

                DispatchQueue.main.async {
                    self.isCapturingKeyframe = false
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        arView.session.delegate = context.coordinator
        arView.session.run(Self.scanConfig())
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let coordinator = context.coordinator

        // 1. Handle export — must happen before any state transition
        if exportTrigger && !coordinator.isExporting {
            coordinator.isExporting = true

            guard let frame = uiView.session.currentFrame else {
                print("[Export] No current frame available")
                coordinator.isExporting = false
                DispatchQueue.main.async { self.exportTrigger = false }
                return
            }

            let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            let keyframes = coordinator.keyframes

            guard !meshAnchors.isEmpty else {
                print("[Export] No mesh anchors found — did you scan a surface?")
                coordinator.isExporting = false
                DispatchQueue.main.async { self.exportTrigger = false }
                return
            }

            print("[Export] Starting with \(meshAnchors.count) mesh anchor(s), \(keyframes.count) keyframe(s)")

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let url = try coordinator.exportViewModel.exportScene(
                        meshAnchors: meshAnchors,
                        keyframes: keyframes
                    )
                    print("[Export] Saved to \(url.lastPathComponent)")
                    DispatchQueue.main.async {
                        coordinator.isExporting = false
                        self.exportedUrl = url
                        self.exportTrigger = false
                    }
                } catch {
                    print("[Export] Failed: \(error)")
                    DispatchQueue.main.async {
                        coordinator.isExporting = false
                        self.exportTrigger = false
                    }
                }
            }
            return
        }

        // 2. Handle state transitions — only on actual change
        let newState = scanState
        let oldState = coordinator.currentState
        guard newState != oldState else { return }
        coordinator.currentState = newState

        switch (oldState, newState) {
        case (.idle, .scanning):
            uiView.debugOptions.insert(.showSceneUnderstanding)
            print("[AR] Scanning started")

        case (.scanning, .paused):
            uiView.session.pause()
            print("[AR] Paused")

        case (.paused, .scanning):
            uiView.debugOptions.insert(.showSceneUnderstanding)
            uiView.session.run(Self.scanConfig())
            print("[AR] Resumed scanning")

        case (.paused, .idle), (.scanning, .idle):
            uiView.debugOptions.remove(.showSceneUnderstanding)
            coordinator.keyframes.removeAll()
            coordinator.lastKeyframePosition = nil
            coordinator.lastKeyframeTime = 0
            uiView.session.run(Self.scanConfig(),
                               options: [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction])
            print("[AR] Reset to idle")

        default:
            print("[AR] Unexpected transition \(oldState) → \(newState)")
        }
    }

    static func scanConfig() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        config.sceneReconstruction = .meshWithClassification
        if type(of: config).supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
        }
        return config
    }
}

class ExportViewModel: NSObject {
    func exportScene(meshAnchors: [ARMeshAnchor], keyframes: [CameraKeyframe]) throws -> URL {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "creating lidar model", code: 153)
        }
        let folderURL = directory.appendingPathComponent("scan_FILES")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let scene = SCNScene()

        for anchor in meshAnchors {
            let meshData = anchor.geometry.extractTexturedMeshData(
                modelMatrix: anchor.transform, keyframes: keyframes
            )

            // Position source
            let positionSource = SCNGeometrySource(vertices: meshData.positions)

            // Texcoord source — pack SIMD2<Float> as contiguous [Float] pairs
            var uvFloats = [Float]()
            uvFloats.reserveCapacity(meshData.texCoords.count * 2)
            for uv in meshData.texCoords {
                uvFloats.append(uv.x)
                uvFloats.append(uv.y)
            }
            let uvData = Data(bytes: uvFloats, count: uvFloats.count * MemoryLayout<Float>.size)
            let texCoordSource = SCNGeometrySource(
                data: uvData,
                semantic: .texcoord,
                vectorCount: meshData.texCoords.count,
                usesFloatComponents: true,
                componentsPerVector: 2,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 2
            )

            // Build one element + material per keyframe group
            var elements: [SCNGeometryElement] = []
            var materials: [SCNMaterial] = []

            for group in meshData.triangleGroups {
                guard !group.indices.isEmpty else { continue }

                let element = SCNGeometryElement(indices: group.indices, primitiveType: .triangles)
                elements.append(element)

                // Decode this keyframe's image lazily (one at a time for memory efficiency)
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.isDoubleSided = true
                if group.keyframeIndex < keyframes.count,
                   let image = UIImage(data: keyframes[group.keyframeIndex].jpegData) {
                    material.diffuse.contents = image
                    material.diffuse.wrapS = .clamp
                    material.diffuse.wrapT = .clamp
                    material.diffuse.magnificationFilter = .linear
                    material.diffuse.minificationFilter = .linear
                    material.diffuse.mipFilter = .linear
                }
                materials.append(material)
            }

            // Fallback element for triangles with no matching keyframe
            if !meshData.fallbackIndices.isEmpty {
                let fallbackElement = SCNGeometryElement(
                    indices: meshData.fallbackIndices, primitiveType: .triangles
                )
                elements.append(fallbackElement)

                let fallbackMaterial = SCNMaterial()
                fallbackMaterial.lightingModel = .constant
                fallbackMaterial.isDoubleSided = true
                fallbackMaterial.diffuse.contents = UIColor.white
                materials.append(fallbackMaterial)
            }

            guard !elements.isEmpty else { continue }

            let geometry = SCNGeometry(
                sources: [positionSource, texCoordSource],
                elements: elements
            )
            geometry.materials = materials

            let node = SCNNode(geometry: geometry)
            scene.rootNode.addChildNode(node)
        }

        let url = folderURL.appendingPathComponent("\(UUID().uuidString).scn")
        let writeDelegate: SCNSceneExportDelegate? = nil
        let writeProgress: SCNSceneExportProgressHandler? = nil
        guard scene.write(to: url, options: nil, delegate: writeDelegate, progressHandler: writeProgress) else {
            throw NSError(domain: "export scene", code: 154,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to write SCN scene"])
        }
        print("[Export] Scene has \(scene.rootNode.childNodes.count) child nodes")
        return url
    }
}
