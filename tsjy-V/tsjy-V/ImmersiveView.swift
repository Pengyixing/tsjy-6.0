import AVFoundation
import ImageIO
import SwiftUI
import RealityKit
import Combine

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var handTracking = HandTrackingManager()
    @State private var sphere: ModelEntity?
    @State private var menuAnchor: Entity?
    @State private var appliedSequence: UInt64 = 0
    @State private var appliedImmersiveSourceID: String?
    @State private var immersivePlayer: AVPlayer?
    @State private var loadTask: Task<Void, Never>?
    @State private var didOpenDefaults = false
    @State private var lastTextureUpdateTime: CFTimeInterval = 0
    @State private var forceShowWristMenu = true
    @State private var wristMenuGraceTask: Task<Void, Never>?
    private let immersiveTextureInterval: CFTimeInterval = 1.0 / 10.0
    private let refreshTimer = Timer.publish(every: 1.0 / 15.0, on: .main, in: .common).autoconnect()

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            let sphere = makePanoramaSphere()
            root.addChild(sphere)
            let anchor = Entity()
            anchor.position = SIMD3<Float>(0, -0.15, -0.65)
            root.addChild(anchor)
            if let menuAttachment = attachments.entity(for: "wristMenu") {
                anchor.addChild(menuAttachment)
            }
            content.add(root)
            self.sphere = sphere
            self.menuAnchor = anchor
            applyCurrentImmersiveContentIfNeeded()
        } update: { _, attachments in
            if let anchor = menuAnchor,
               let menuAttachment = attachments.entity(for: "wristMenu"),
               menuAttachment.parent == nil {
                anchor.addChild(menuAttachment)
            }
            applyCurrentImmersiveContentIfNeeded()
        } attachments: {
            Attachment(id: "wristMenu") {
                WristMenuView(onSelectSource: { source in
                    appModel.openSource(id: source.id)
                    if appModel.pendingOpen == .web {
                        openWindow(id: "webViewWindow", value: source.id)
                    } else if appModel.pendingOpen == .video {
                        openWindow(id: "videoWindow", value: source.id)
                    }
                }, onOpenControl: {
                    openWindow(id: "controlWindow")
                })
                .environment(appModel)
                .opacity(Self.wristMenuVisibility(
                    isUIFixed: appModel.isUIFixed,
                    isWristVisible: handTracking.isWristVisible,
                    forceVisible: forceShowWristMenu
                ))
                .scaleEffect(Self.wristMenuScale(
                    isUIFixed: appModel.isUIFixed,
                    isWristVisible: handTracking.isWristVisible,
                    forceVisible: forceShowWristMenu
                ))
                .animation(.easeInOut(duration: 0.25), value: handTracking.isWristVisible)
                .animation(.easeInOut(duration: 0.25), value: appModel.isUIFixed)
                .animation(.easeInOut(duration: 0.25), value: forceShowWristMenu)
            }
        }
        .task {
            prepareWristMenuForEntry()
            await handTracking.start()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                openDefaultSourcesIfNeeded()
            }
        }
        .onDisappear {
            handTracking.stop()
            loadTask?.cancel()
            wristMenuGraceTask?.cancel()
            immersivePlayer?.pause()
            sphere = nil
            menuAnchor = nil
            forceShowWristMenu = true
        }
        .onChange(of: handTracking.leftWristTransform) { _, matrix in
            updateWristMenuTransform(matrix)
        }
        .onChange(of: appModel.defaultSourceIDs) { _, _ in
            openDefaultSourcesIfNeeded()
        }
        .onChange(of: appModel.immersivePanoramaSourceID) { _, _ in
            applyCurrentImmersiveContentIfNeeded()
        }
        .onChange(of: appModel.latestFrameSequence) { _, _ in
            applyCurrentImmersiveContentIfNeeded()
        }
        .onReceive(refreshTimer) { _ in
            applyCurrentImmersiveContentIfNeeded()
        }
    }

    private func makePanoramaSphere() -> ModelEntity {
        let mesh = (try? Self.buildInsideSphere(radius: 12, latSegments: 64, lonSegments: 128))
            ?? .generateSphere(radius: 12)
        return ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
    }

    private func openDefaultSourcesIfNeeded() {
        guard !didOpenDefaults, !appModel.defaultSourceIDs.isEmpty else { return }
        didOpenDefaults = true
        for sourceID in appModel.defaultSourceIDs {
            appModel.openSource(id: sourceID)
            if appModel.pendingOpen == .web {
                openWindow(id: "webViewWindow", value: sourceID)
            } else if appModel.pendingOpen == .video {
                openWindow(id: "videoWindow", value: sourceID)
            }
        }
    }

    private func updateWristMenuTransform(_ matrix: simd_float4x4?) {
        guard !appModel.isUIFixed else { return }
        guard let matrix, let menuAnchor else { return }

        let wristTransform = Transform(matrix: matrix)
        let localOffset = SIMD3<Float>(0.08, 0.08, 0.0)
        let worldOffset = wristTransform.rotation.act(localOffset)

        menuAnchor.position = wristTransform.translation + worldOffset

        let xRot = simd_quatf(angle: -.pi / 3, axis: SIMD3<Float>(1, 0, 0))
        let yRot = simd_quatf(angle: .pi / 8, axis: SIMD3<Float>(0, 1, 0))
        let zRot = simd_quatf(angle: -.pi / 16, axis: SIMD3<Float>(0, 0, 1))
        menuAnchor.orientation = wristTransform.rotation * xRot * yRot * zRot
    }

    private func prepareWristMenuForEntry() {
        wristMenuGraceTask?.cancel()
        forceShowWristMenu = true
        wristMenuGraceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            forceShowWristMenu = false
        }
    }

    private func applyCurrentImmersiveContentIfNeeded() {
        if let source = appModel.immersivePanoramaSource, source.type.isPanoramaScene {
            applyPanoramaSourceIfNeeded(source)
        } else {
            applyLatestFrameIfNeeded()
        }
    }

    private func applyLatestFrameIfNeeded() {
        guard let sphere,
              appliedSequence != appModel.latestFrameSequence,
              let image = appModel.latestFrameImage else {
            return
        }

        loadTask?.cancel()
        loadTask = nil
        immersivePlayer?.pause()
        immersivePlayer = nil
        appliedImmersiveSourceID = nil

        guard appModel.isPanoramaEligible else {
            sphere.model?.materials = [UnlitMaterial(color: .black)]
            appliedSequence = appModel.latestFrameSequence
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastTextureUpdateTime >= immersiveTextureInterval else {
            return
        }

        do {
            let texture = try TextureResource(image: image, options: .init(semantic: .color))
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            sphere.model?.materials = [material]
            appliedSequence = appModel.latestFrameSequence
            lastTextureUpdateTime = now
        } catch {
            sphere.model?.materials = [UnlitMaterial(color: .black)]
        }
    }

    private func applyPanoramaSourceIfNeeded(_ source: ContentSourceItem) {
        guard appliedImmersiveSourceID != source.id else { return }

        appliedImmersiveSourceID = source.id
        loadTask?.cancel()
        loadTask = nil
        immersivePlayer?.pause()
        immersivePlayer = nil

        sphere?.model?.materials = [UnlitMaterial(color: .black)]
        loadTask = Task {
            do {
                guard let url = await appModel.localPlaybackURL(for: source) else {
                    return
                }

                guard !Task.isCancelled else { return }

                if source.type == .panoramaVideo {
                    await MainActor.run {
                        guard appModel.immersivePanoramaSourceID == source.id else { return }
                        guard let sphere = self.sphere else { return }
                        let player = AVPlayer(url: url)
                        player.isMuted = source.muted ?? true
                        player.play()
                        immersivePlayer = player
                        sphere.model?.materials = [VideoMaterial(avPlayer: player)]
                    }
                    return
                }

                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    throw URLError(.cannotDecodeContentData)
                }
                let texture = try await TextureResource(image: image, options: .init(semantic: .color))
                await MainActor.run {
                    guard appModel.immersivePanoramaSourceID == source.id else { return }
                    guard let sphere = self.sphere else { return }
                    var material = UnlitMaterial()
                    material.color = .init(texture: .init(texture))
                    sphere.model?.materials = [material]
                }
            } catch {
                await MainActor.run {
                    guard appModel.immersivePanoramaSourceID == source.id else { return }
                    self.sphere?.model?.materials = [UnlitMaterial(color: .black)]
                }
            }
        }
    }

    private static func buildInsideSphere(
        radius: Float,
        latSegments: UInt32,
        lonSegments: UInt32
    ) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        let lonCount = lonSegments + 1

        for lat in 0...latSegments {
            let theta = Float(lat) * .pi / Float(latSegments)
            let sinT = sin(theta)
            let cosT = cos(theta)

            for lon in 0...lonSegments {
                let phi = Float(lon) * 2 * .pi / Float(lonSegments)
                let sinP = sin(phi)
                let cosP = cos(phi)

                let x = cosP * sinT
                let y = cosT
                let z = sinP * sinT

                positions.append(SIMD3<Float>(x, y, z) * radius)
                normals.append(-SIMD3<Float>(x, y, z))
                uvs.append(
                    SIMD2<Float>(
                        Float(lon) / Float(lonSegments),
                        1.0 - Float(lat) / Float(latSegments)
                    )
                )
            }
        }

        for lat in 0..<latSegments {
            for lon in 0..<lonSegments {
                let tl = lat * lonCount + lon
                let tr = lat * lonCount + lon + 1
                let bl = (lat + 1) * lonCount + lon
                let br = (lat + 1) * lonCount + lon + 1

                indices += [tl, bl, tr]
                indices += [tr, bl, br]
            }
        }

        var descriptor = MeshDescriptor(name: "InsideOutSphere")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }

    static func wristMenuVisibility(isUIFixed: Bool, isWristVisible: Bool, forceVisible: Bool) -> Double {
        if isUIFixed || isWristVisible || forceVisible {
            return 1.0
        }
        return 0.0
    }

    static func wristMenuScale(isUIFixed: Bool, isWristVisible: Bool, forceVisible: Bool) -> Double {
        if isUIFixed || isWristVisible || forceVisible {
            return 1.0
        }
        return 0.85
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
