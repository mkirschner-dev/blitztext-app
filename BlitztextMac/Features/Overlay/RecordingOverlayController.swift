import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayController {
    private let panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 134, height: 134),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        return panel
    }()

    func show(appState: AppState) {
        panel.contentView = NSHostingView(
            rootView: RecordingOverlayView(appState: appState) { [weak self] isVisible in
                self?.setVisible(isVisible)
            }
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange() {
        positionPanel()
    }

    private func setVisible(_ isVisible: Bool) {
        if isVisible {
            positionPanel()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func positionPanel() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let panelSize = NSSize(width: 134, height: 134)
        let safeFrame = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let origin = NSPoint(
            x: max(safeFrame.minX, safeFrame.maxX - panelSize.width),
            y: safeFrame.minY
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
    }
}

private struct RecordingOverlayView: View {
    let appState: AppState
    let onVisibilityChange: (Bool) -> Void

    private var workflow: (any Workflow)? {
        guard let workflow = appState.activeWorkflow, workflow.phase.isActive else { return nil }
        return workflow
    }

    private var isRecording: Bool {
        workflow?.isRecording == true
    }

    private var isProcessing: Bool {
        guard let workflow else { return false }
        if case .running = workflow.phase { return !workflow.isRecording }
        return false
    }

    private var audioLevel: Float {
        isRecording ? (workflow?.audioLevel ?? 0) : 0
    }

    var body: some View {
        Group {
            if isRecording || isProcessing {
                Group {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.9))
                            .scaleEffect(1.25)
                    } else {
                        ParticleGlobeView(audioLevel: audioLevel)
                    }
                }
                .frame(width: 134, height: 134)
                .background(Color(red: 0.13, green: 0.15, blue: 0.18), in: Circle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isRecording ? "Blitztext nimmt Sprache auf" : "Blitztext verarbeitet Sprache")
            }
        }
        .onAppear {
            onVisibilityChange(isRecording || isProcessing)
        }
        .onChange(of: isRecording || isProcessing) { _, isVisible in
            onVisibilityChange(isVisible)
        }
    }

}

private struct GlobeParticle {
    let x: Double
    let y: Double
    let z: Double
    let brightness: Double
    let size: Double
    let phase: Double
    let isTurquoise: Bool
}

private struct ParticleGlobeView: View {
    let audioLevel: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let particles: [GlobeParticle] = {
        let count = 320
        func sample(_ seed: Int) -> Double {
            let value = sin(Double(seed + 1) * 127.1) * 43758.5453
            return value - floor(value)
        }
        return (0..<count).map { index in
            // Scatter over a sphere so rotation moves particles through real depth.
            let z = sample(index * 6) * 2 - 1
            let angle = sample(index * 6 + 1) * 2 * Double.pi
            let ringRadius = sqrt(1 - z * z)
            return GlobeParticle(
                x: cos(angle) * ringRadius,
                y: sin(angle) * ringRadius,
                z: z,
                brightness: 0.45 + sample(index * 6 + 2) * 0.4,
                size: 0.65 + sample(index * 6 + 3) * 0.65,
                phase: sample(index * 6 + 4) * 2 * Double.pi,
                isTurquoise: sample(index * 6 + 5) < 0.22
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120 * Double.pi)
                let level = pow(min(1, max(0, (Double(audioLevel) - 0.1) / 0.9)), 0.65)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.35
                let rotation = time * 0.4
                let tilt = 0.3
                let pulse = 1 + (reduceMotion ? 0 : sin(time * 2) * 0.025) + level * 0.09
                let cosRotation = cos(rotation)
                let sinRotation = sin(rotation)

                for particle in Self.particles {
                    let x = particle.x * cosRotation + particle.z * sinRotation
                    let rotatedZ = particle.z * cosRotation - particle.x * sinRotation
                    let y = particle.y * cos(tilt) - rotatedZ * sin(tilt)
                    let z = particle.y * sin(tilt) + rotatedZ * cos(tilt)
                    let depth = (z + 1) / 2
                    // Traveling waves reshape the surface; each dot also has its own bounce.
                    let surfaceWave = sin(time * 5 + particle.y * 4 + particle.x * 3)
                        * cos(time * 3 - particle.z * 4)
                    let bounce = sin(time * 8 + particle.phase)
                    let ripple = reduceMotion ? 0 : surfaceWave * (0.018 + level * 0.17)
                        + bounce * (0.006 + level * 0.075)
                    let verticalBounce = reduceMotion ? 0 : sin(time * 7 + particle.phase) * level * radius * 0.09
                    let scale = (pulse + ripple) * (1 + z * 0.08)
                    let dotSize = particle.size * (0.65 + depth * 0.6) * (1 + level * 0.55)
                    let point = CGPoint(
                        x: center.x + x * radius * scale,
                        y: center.y + y * radius * scale + verticalBounce
                    )
                    let rect = CGRect(
                        x: point.x - dotSize / 2,
                        y: point.y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )

                    let color = particle.isTurquoise
                        ? Color(red: 0.40, green: 0.85, blue: 0.80)
                        : Color(red: 0.91, green: 0.94, blue: 0.96)
                    let opacity = min(1, 0.48 + depth * 0.36 + level * 0.10)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
                }
            }
        }
        .frame(width: 92, height: 92)
        .scaleEffect(4.0 / 3.0)
        .frame(width: 123, height: 123)
        .accessibilityHidden(true)
    }
}
