////  Mesh+Ext.swift
//  AnchorMap
//  Created by Ahmed Shousha on 10/12/2025.
// code from:
//  VirtualShowrooms
//  Created by Kelvin J on 5/25/23.
//

import RealityKit
import ARKit
import SceneKit

struct MeshData {
    let positions: [SCNVector3]
    let colors: [SIMD3<Float>]
    let indices: [UInt32]
}

extension ARMeshGeometry {
    func vertex(at index: UInt32) -> SIMD3<Float> {
        assert(vertices.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per vertex.")
        let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (vertices.stride * Int(index)))
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        return vertex
    }

    func extractMeshData(modelMatrix: simd_float4x4, keyframes: [CameraKeyframe]) -> MeshData {
        var worldVertices: [SIMD3<Float>] = []
        var vertexColors: [SIMD3<Float>] = []

        // Convert vertices from local to world space
        for vertexIndex in 0..<vertices.count {
            let vertex = self.vertex(at: UInt32(vertexIndex))
            var vertexLocalTransform = matrix_identity_float4x4
            vertexLocalTransform.columns.3 = SIMD4<Float>(x: vertex.x, y: vertex.y, z: vertex.z, w: 1)
            let vertexWorldPosition = (modelMatrix * vertexLocalTransform).columns.3
            worldVertices.append(SIMD3<Float>(vertexWorldPosition.x, vertexWorldPosition.y, vertexWorldPosition.z))
        }

        // Extract face indices
        let indexCount = faces.count * faces.indexCountPerPrimitive
        let indicesPtr = faces.buffer.contents().assumingMemoryBound(to: UInt32.self)
        var indices = [UInt32]()
        indices.reserveCapacity(indexCount)
        for i in 0..<indexCount {
            indices.append(indicesPtr[i])
        }

        // Color each vertex from the best keyframe
        if keyframes.isEmpty {
            vertexColors = Array(repeating: SIMD3<Float>(1.0, 1.0, 1.0), count: worldVertices.count)
        } else {
            var bestKeyframeIndex = [Int](repeating: -1, count: worldVertices.count)
            var bestScore = [Float](repeating: -Float.greatestFiniteMagnitude, count: worldVertices.count)
            var bestPixelX = [Float](repeating: 0, count: worldVertices.count)
            var bestPixelY = [Float](repeating: 0, count: worldVertices.count)

            // Pre-compute per-keyframe data
            struct KeyframeData {
                let camForward: simd_float3
                let viewProj: simd_float4x4
                let position: simd_float3
                let imageWidth: Int
                let imageHeight: Int
            }
            let keyframeData = keyframes.map { kf -> KeyframeData in
                KeyframeData(
                    camForward: simd_float3(
                        -kf.viewMatrix.columns.0.z,
                        -kf.viewMatrix.columns.1.z,
                        -kf.viewMatrix.columns.2.z
                    ),
                    viewProj: kf.projectionMatrix * kf.viewMatrix,
                    position: kf.position,
                    imageWidth: kf.imageWidth,
                    imageHeight: kf.imageHeight
                )
            }

            let vertexCount = worldVertices.count
            DispatchQueue.concurrentPerform(iterations: vertexCount) { vIdx in
                let worldPos = worldVertices[vIdx]
                var localBestScore: Float = -Float.greatestFiniteMagnitude
                var localBestKF = -1
                var localBestFX: Float = 0
                var localBestFY: Float = 0

                for (kfIndex, kf) in keyframeData.enumerated() {
                    // Early distance cull: skip keyframes >10m away
                    let dist = simd_distance(worldPos, kf.position)
                    guard dist <= 10.0 else { continue }

                    let worldPos4 = SIMD4<Float>(worldPos.x, worldPos.y, worldPos.z, 1.0)
                    let clipSpace = kf.viewProj * worldPos4
                    guard clipSpace.w > 0 else { continue }

                    let ndcX = clipSpace.x / clipSpace.w
                    let ndcY = clipSpace.y / clipSpace.w

                    let margin: Float = 0.05
                    guard ndcX >= -1.0 + margin, ndcX <= 1.0 - margin,
                          ndcY >= -1.0 + margin, ndcY <= 1.0 - margin else { continue }

                    let fx = (ndcX + 1.0) * 0.5 * Float(kf.imageWidth) - 0.5
                    let fy = (1.0 - ndcY) * 0.5 * Float(kf.imageHeight) - 0.5

                    guard fx >= 0, fx < Float(kf.imageWidth - 1),
                          fy >= 0, fy < Float(kf.imageHeight - 1) else { continue }

                    let vertexDir = simd_normalize(worldPos - kf.position)
                    let dot = simd_dot(kf.camForward, vertexDir)
                    let distancePenalty = 1.0 / (1.0 + 0.5 * dist)
                    let centerBonus = 1.0 - 0.15 * (ndcX * ndcX + ndcY * ndcY)
                    let score = dot * distancePenalty * centerBonus

                    if score > localBestScore {
                        localBestScore = score
                        localBestKF = kfIndex
                        localBestFX = fx
                        localBestFY = fy
                    }
                }

                bestScore[vIdx] = localBestScore
                bestKeyframeIndex[vIdx] = localBestKF
                bestPixelX[vIdx] = localBestFX
                bestPixelY[vIdx] = localBestFY
            }

            // Group vertices by best keyframe, decompress each JPEG once
            var verticesByKeyframe: [Int: [(vertexIdx: Int, fx: Float, fy: Float)]] = [:]
            for vIdx in 0..<worldVertices.count {
                verticesByKeyframe[bestKeyframeIndex[vIdx], default: []].append((vIdx, bestPixelX[vIdx], bestPixelY[vIdx]))
            }

            vertexColors = Array(repeating: SIMD3<Float>(1.0, 1.0, 1.0), count: worldVertices.count)
            var coloredCount = 0

            for (kfIdx, vertexEntries) in verticesByKeyframe {
                guard kfIdx >= 0, kfIdx < keyframes.count else { continue }
                let keyframe = keyframes[kfIdx]

                guard let uiImage = UIImage(data: keyframe.jpegData),
                      let cgImage = uiImage.cgImage,
                      let dataProvider = cgImage.dataProvider,
                      let pixelData = dataProvider.data else { continue }

                let ptr: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
                let bytesPerPixel = cgImage.bitsPerPixel / 8
                let bytesPerRow = cgImage.bytesPerRow
                let width = cgImage.width
                let height = cgImage.height

                for entry in vertexEntries {
                    // Bilinear interpolation: sample 4 nearest pixels and blend
                    let x0 = Int(floor(entry.fx))
                    let y0 = Int(floor(entry.fy))
                    let x1 = min(x0 + 1, width - 1)
                    let y1 = min(y0 + 1, height - 1)

                    guard x0 >= 0, x0 < width, y0 >= 0, y0 < height else { continue }

                    let sx = entry.fx - Float(x0)
                    let sy = entry.fy - Float(y0)

                    let off00 = y0 * bytesPerRow + x0 * bytesPerPixel
                    let off10 = y0 * bytesPerRow + x1 * bytesPerPixel
                    let off01 = y1 * bytesPerRow + x0 * bytesPerPixel
                    let off11 = y1 * bytesPerRow + x1 * bytesPerPixel

                    let w00 = (1.0 - sx) * (1.0 - sy)
                    let w10 = sx * (1.0 - sy)
                    let w01 = (1.0 - sx) * sy
                    let w11 = sx * sy

                    let r = (w00 * Float(ptr[off00]) + w10 * Float(ptr[off10]) + w01 * Float(ptr[off01]) + w11 * Float(ptr[off11])) / 255.0
                    let g = (w00 * Float(ptr[off00 + 1]) + w10 * Float(ptr[off10 + 1]) + w01 * Float(ptr[off01 + 1]) + w11 * Float(ptr[off11 + 1])) / 255.0
                    let b = (w00 * Float(ptr[off00 + 2]) + w10 * Float(ptr[off10 + 2]) + w01 * Float(ptr[off01 + 2]) + w11 * Float(ptr[off11 + 2])) / 255.0
                    vertexColors[entry.vertexIdx] = SIMD3<Float>(r, g, b)
                    coloredCount += 1
                }
            }

            print("[Color] \(coloredCount)/\(worldVertices.count) vertices colored from \(keyframes.count) keyframes")
        }

        let positions = worldVertices.map { SCNVector3($0.x, $0.y, $0.z) }
        return MeshData(positions: positions, colors: vertexColors, indices: indices)
    }
}
