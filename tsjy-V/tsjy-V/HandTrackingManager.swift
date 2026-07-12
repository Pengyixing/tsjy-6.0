import ARKit
import Combine
import RealityKit
import SwiftUI
import QuartzCore

@MainActor
final class HandTrackingManager: ObservableObject {
    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private let worldTracking = WorldTrackingProvider()

    @Published var leftWristTransform: simd_float4x4?
    @Published var isWristVisible = false

    private var visibleTickCount = 0
    private var hiddenTickCount = 0
    private let showThreshold = 3
    private let hideThreshold = 8
    private var trackingTask: Task<Void, Never>?

    func start() async {
        guard HandTrackingProvider.isSupported, WorldTrackingProvider.isSupported else { return }
        resetTrackingState()
        do {
            try await session.run([handTracking, worldTracking])
            trackingTask?.cancel()
            trackingTask = Task {
                await processHandUpdates()
            }
        } catch {
            print("手部追踪启动失败: \(error.localizedDescription)")
        }
    }

    func stop() {
        trackingTask?.cancel()
        trackingTask = nil
        session.stop()
        resetTrackingState()
    }

    private func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor
            guard anchor.chirality == .left else { continue }
            guard anchor.handSkeleton != nil else { continue }

            if anchor.isTracked {
                let transform = anchor.originFromAnchorTransform
                leftWristTransform = transform

                // Get device transform
                let deviceTransform: simd_float4x4?
                if let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                    deviceTransform = deviceAnchor.originFromAnchorTransform
                } else {
                    deviceTransform = nil
                }

                if isWristGestureVisible(transform: transform, deviceTransform: deviceTransform) {
                    visibleTickCount += 1
                    hiddenTickCount = 0
                    if visibleTickCount >= showThreshold {
                        isWristVisible = true
                    }
                } else {
                    hiddenTickCount += 1
                    visibleTickCount = 0
                    if hiddenTickCount >= hideThreshold {
                        isWristVisible = false
                    }
                }
            } else {
                hiddenTickCount += 1
                visibleTickCount = 0
                if hiddenTickCount >= hideThreshold {
                    isWristVisible = false
                }
            }
        }
    }

    private func isWristGestureVisible(transform: simd_float4x4, deviceTransform: simd_float4x4?) -> Bool {
        guard let deviceTransform = deviceTransform else {
            // Fallback if no device transform
            return true
        }

        // Calculate hand position relative to the device (head)
        let deviceInverse = deviceTransform.inverse
        let handRelativeToDevice = deviceInverse * transform
        let position = handRelativeToDevice.columns.3

        // Head coordinate system:
        // +X is right, -X is left
        // +Y is up, -Y is down
        // -Z is forward, +Z is backward

        // Check if hand is somewhat in front of the face and raised
        let isRaised = position.y > -0.6 && position.y < 0.2 // Between chest and eye level
        let isInFront = position.z < -0.1 && position.z > -0.8 // Between 10cm and 80cm in front

        return isRaised && isInFront
    }

    private func resetTrackingState() {
        leftWristTransform = nil
        isWristVisible = false
        visibleTickCount = 0
        hiddenTickCount = 0
    }
}
