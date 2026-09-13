import SwiftUI
import SceneKit
import HealthCore

/// A stylized 3D mannequin built from SceneKit primitives — no external
/// assets, matches the clinical-calm aesthetic. Swipe to orbit (yaw free,
/// pitch clamped), with inertia; idle slow-spin until first touch; tap a
/// marker to open that region's episodes.
struct Body3DView: UIViewRepresentable {
    let regionData: [BodyRegion: (count: Int, maxSeverity: Int)]
    let onSelect: (BodyRegion) -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.buildScene()
        context.coordinator.attachGestures(to: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.updateMarkers(regionData)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(regionData: regionData, onSelect: onSelect)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (BodyRegion) -> Void
        private var regionData: [BodyRegion: (count: Int, maxSeverity: Int)]
        private let bodyNode = SCNNode()
        private var pitchNode = SCNNode()
        private var markerNodes: [BodyRegion: SCNNode] = [:]
        private var hasInteracted = false

        init(regionData: [BodyRegion: (count: Int, maxSeverity: Int)], onSelect: @escaping (BodyRegion) -> Void) {
            self.regionData = regionData
            self.onSelect = onSelect
        }

        // MARK: Scene construction

        func buildScene() -> SCNScene {
            let scene = SCNScene()

            // Camera (framed for the 1.69m mesh standing at y=0)
            let camera = SCNCamera()
            camera.fieldOfView = 30
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0.92, 4.5)
            cameraNode.look(at: SCNVector3(0, 0.80, 0))
            scene.rootNode.addChildNode(cameraNode)

            // Lighting: soft key + ambient fill, no harsh shadows
            let key = SCNNode()
            key.light = SCNLight()
            key.light!.type = .directional
            key.light!.intensity = 650
            key.eulerAngles = SCNVector3(-0.6, 0.5, 0)
            scene.rootNode.addChildNode(key)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light!.type = .ambient
            ambient.light!.intensity = 550
            scene.rootNode.addChildNode(ambient)

            // pitchNode (x-axis clamp) → bodyNode (free yaw)
            pitchNode.addChildNode(bodyNode)
            scene.rootNode.addChildNode(pitchNode)

            loadBody(into: bodyNode)
            updateMarkers(regionData)
            startIdleSpin()
            return scene
        }

        /// Loads the CC0 Blender Studio realistic human base mesh (bundled OBJ).
        /// Falls back to the primitive mannequin if the asset is missing.
        private func loadBody(into root: SCNNode) {
            guard let scene = SCNScene(named: "Art.scnassets/human_body.obj") else {
                buildMannequin(into: root)
                return
            }
            let material = bodyMaterial()
            for child in scene.rootNode.childNodes {
                let node = child.clone()
                node.enumerateHierarchy { n, _ in
                    n.geometry?.materials = [material]
                }
                root.addChildNode(node)
            }
        }

        private func bodyMaterial() -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = UIColor.systemGray5
            m.roughness.contents = 0.85
            m.metalness.contents = 0.0
            return m
        }

        private func part(_ geometry: SCNGeometry, x: Float, y: Float, z: Float = 0, euler: SCNVector3 = SCNVector3Zero) -> SCNNode {
            geometry.materials = [bodyMaterial()]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x, y, z)
            node.eulerAngles = euler
            return node
        }

        private func buildMannequin(into root: SCNNode) {
            // Head + neck
            root.addChildNode(part(SCNSphere(radius: 0.115), x: 0, y: 1.475))
            root.addChildNode(part(SCNCylinder(radius: 0.045, height: 0.10), x: 0, y: 1.33))
            // Torso (slightly flattened capsule) + pelvis
            let torso = SCNCapsule(capRadius: 0.165, height: 0.62)
            let torsoNode = part(torso, x: 0, y: 1.0)
            torsoNode.scale = SCNVector3(1.0, 1.0, 0.62)
            root.addChildNode(torsoNode)
            let pelvis = part(SCNCapsule(capRadius: 0.15, height: 0.24), x: 0, y: 0.66)
            pelvis.scale = SCNVector3(1.0, 1.0, 0.62)
            root.addChildNode(pelvis)
            // Arms (slightly angled out)
            for side: Float in [-1, 1] {
                let upper = part(SCNCapsule(capRadius: 0.052, height: 0.40), x: side * 0.245, y: 1.06, euler: SCNVector3(0, 0, side * -0.12))
                root.addChildNode(upper)
                let lower = part(SCNCapsule(capRadius: 0.045, height: 0.38), x: side * 0.285, y: 0.70, euler: SCNVector3(0, 0, side * -0.06))
                root.addChildNode(lower)
            }
            // Legs
            for side: Float in [-1, 1] {
                root.addChildNode(part(SCNCapsule(capRadius: 0.07, height: 0.52), x: side * 0.095, y: 0.34))
                root.addChildNode(part(SCNCapsule(capRadius: 0.058, height: 0.46), x: side * 0.10, y: -0.10))
            }
        }

        /// Marker anchor points on the mesh surface (mesh: feet y=0, height 1.69,
        /// A-pose ±0.44 wide, torso front z ≈ +0.11, back z ≈ -0.11).
        private func anchor(for region: BodyRegion) -> SCNVector3? {
            switch region {
            case .head: SCNVector3(0, 1.60, 0.10)
            case .throat: SCNVector3(0, 1.43, 0.07)
            case .chest: SCNVector3(0, 1.24, 0.11)
            case .abdomen: SCNVector3(0, 1.02, 0.11)
            case .back: SCNVector3(0, 1.13, -0.11)
            case .arms: SCNVector3(0.28, 1.05, 0.02)
            case .legs: SCNVector3(0.10, 0.47, 0.07)
            case .skin, .systemic: nil
            }
        }

        func updateMarkers(_ data: [BodyRegion: (count: Int, maxSeverity: Int)]) {
            regionData = data
            markerNodes.values.forEach { $0.removeFromParentNode() }
            markerNodes.removeAll()

            for (region, stats) in data {
                guard let position = anchor(for: region) else { continue }

                let radius = min(0.055 + 0.006 * CGFloat(stats.count), 0.13)
                let sphere = SCNSphere(radius: radius)
                let material = SCNMaterial()
                let color = UIColor(Color.severity(stats.maxSeverity))
                material.diffuse.contents = color
                material.emission.contents = color.withAlphaComponent(0.75)
                sphere.materials = [material]

                let marker = SCNNode(geometry: sphere)
                marker.position = position
                marker.name = "region_\(region.rawValue)"

                // Count label, billboarded so it always faces the camera.
                let text = SCNText(string: "\(stats.count)", extrusionDepth: 0.1)
                text.font = .systemFont(ofSize: 10, weight: .bold)
                text.firstMaterial?.diffuse.contents = UIColor.white
                text.firstMaterial?.emission.contents = UIColor.white
                text.flatness = 0.1
                // Draw on top of the sphere regardless of body rotation.
                text.firstMaterial?.readsFromDepthBuffer = false
                let label = SCNNode(geometry: text)
                let (minB, maxB) = label.boundingBox
                label.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
                label.scale = SCNVector3(0.010, 0.010, 0.010)
                label.position = SCNVector3(0, 0, 0)
                label.renderingOrder = 100
                label.constraints = [SCNBillboardConstraint()]
                label.name = marker.name
                marker.addChildNode(label)

                // Gentle breathing pulse on the most severe region.
                if stats.maxSeverity >= 7 {
                    let pulse = SCNAction.sequence([
                        .scale(to: 1.12, duration: 0.9),
                        .scale(to: 1.0, duration: 0.9)
                    ])
                    pulse.timingMode = .easeInEaseOut
                    marker.runAction(.repeatForever(pulse))
                }

                bodyNode.addChildNode(marker)
                markerNodes[region] = marker
            }
        }

        // MARK: Interaction

        private func startIdleSpin() {
            let spin = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 26)
            bodyNode.runAction(.repeatForever(spin), forKey: "idleSpin")
        }

        func attachGestures(to view: SCNView) {
            view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            if !hasInteracted {
                hasInteracted = true
                bodyNode.removeAction(forKey: "idleSpin")
            }
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)

            bodyNode.eulerAngles.y += Float(translation.x) * 0.012
            let pitch = pitchNode.eulerAngles.x + Float(translation.y) * 0.008
            pitchNode.eulerAngles.x = max(-0.30, min(0.30, pitch))

            if gesture.state == .ended {
                // Inertia: decay the fling into a short eased rotation.
                let velocity = gesture.velocity(in: gesture.view).x
                let carry = SCNAction.rotateBy(x: 0, y: CGFloat(velocity) * 0.0009, z: 0, duration: 0.7)
                carry.timingMode = .easeOut
                bodyNode.runAction(carry)
            }
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            for hit in hits {
                if let name = hit.node.name, name.hasPrefix("region_"),
                   let region = BodyRegion(rawValue: String(name.dropFirst("region_".count))) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(region)
                    return
                }
            }
        }
    }
}
