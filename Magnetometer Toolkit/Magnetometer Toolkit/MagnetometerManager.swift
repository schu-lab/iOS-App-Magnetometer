import Foundation
import CoreMotion
import CoreLocation

/// Magnetometer + heading manager with switchable RAW / CALIBRATED modes.
/// Includes serialized mode switching + UI throttling to reduce stalls.
final class MagnetometerManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: Data mode
    enum DataMode: String, CaseIterable, Identifiable {
        case calibrated = "Calibrated"
        case raw = "Raw"
        var id: String { rawValue }
    }

    /// User-selected mode (bind to UI)
    @Published var mode: DataMode = .calibrated
    /// What we’re actually running right now (e.g., raw fallback if calibrated unavailable)
    @Published private(set) var activeMode: DataMode = .calibrated

    // MARK: Published measurements (microtesla)
    @Published var magX: Double = 0
    @Published var magY: Double = 0
    @Published var magZ: Double = 0
    @Published var magnitude: Double = 0

    // Heading (degrees)
    @Published var magneticHeading: Double = 0
    @Published var trueHeading: Double? = nil
    @Published var headingAccuracy: Double = 0

    // Availability / auth
    @Published var locationAuthStatus: CLAuthorizationStatus = .notDetermined
    @Published var headingAvailable: Bool = CLLocationManager.headingAvailable()

    // Calibration info (only when using deviceMotion)
    @Published var calibrationAccuracy: CMMagneticFieldCalibrationAccuracy = .uncalibrated

    // Switching guard
    @Published var isSwitchingMode: Bool = false

    private let motion = CMMotionManager()
    private let loc = CLLocationManager()

    // Motion callbacks on a serialized queue
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "MagnetometerManager.motion"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        return q
    }()

    // Serialize applyMode and stop/start
    private let serial = DispatchQueue(label: "MagnetometerManager.serial")

    // UI throttle (~20 Hz publishes to reduce SwiftUI load)
    private var lastUIStamp: TimeInterval = 0
    private let minUIInterval: TimeInterval = 1.0 / 20.0

    override init() {
        super.init()
        loc.delegate = self
        loc.headingFilter = 1
        loc.requestWhenInUseAuthorization()
    }

    // MARK: Lifecycle
    func start() {
        startHeading()
        applyMode(mode) // start the selected stream
    }

    func stop() {
        loc.stopUpdatingHeading()
        stopMagStreams()
    }

    // MARK: Mode switching (debounced & serialized)
    func applyMode(_ newMode: DataMode) {
        guard !isSwitchingMode else { return }
        isSwitchingMode = true
        serial.async { [weak self] in
            guard let self else { return }
            self.stopMagStreams()
            switch newMode {
            case .calibrated:
                if self.motion.isDeviceMotionAvailable {
                    self.startCalibrated()
                    self.activeMode = .calibrated
                } else {
                    self.startRaw()
                    self.activeMode = .raw
                }
            case .raw:
                self.startRaw()
                self.activeMode = .raw
            }
            // brief guard against rapid toggles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.isSwitchingMode = false
            }
        }
    }

    private func stopMagStreams() {
        motion.stopDeviceMotionUpdates()
        motion.stopMagnetometerUpdates()
    }

    // MARK: Heading (Core Location)
    private func startHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        loc.startUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            startHeading()
        } else {
            loc.stopUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        magneticHeading = fmod(newHeading.magneticHeading + 360, 360)
        trueHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil
        headingAccuracy = newHeading.headingAccuracy
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }

    // MARK: Magnetics
    /// Calibrated magnetics via CMDeviceMotion (bias-corrected µT)
    private func startCalibrated() {
        motion.deviceMotionUpdateInterval = 1.0 / 20.0 // 20 Hz
        motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: motionQueue) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let f = dm.magneticField
            self.calibrationAccuracy = f.accuracy
            let x = f.field.x, y = f.field.y, z = f.field.z
            let mag = sqrt(x*x + y*y + z*z)
            self.dispatchUI(x: x, y: y, z: z, mag: mag)
        }
    }

    /// RAW magnetics via CMMotionManager (uncorrected µT; includes hard/soft-iron effects)
    private func startRaw() {
        guard motion.isMagnetometerAvailable else { return }
        motion.magnetometerUpdateInterval = 1.0 / 20.0 // 20 Hz
        motion.startMagnetometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let m = data?.magneticField else { return }
            let x = m.x, y = m.y, z = m.z
            let mag = sqrt(x*x + y*y + z*z)
            self.dispatchUI(x: x, y: y, z: z, mag: mag)
        }
    }

    // Throttle main-thread publishes to ~20 Hz to avoid UI stalls when toggling
    private func dispatchUI(x: Double, y: Double, z: Double, mag: Double) {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastUIStamp < minUIInterval { return }
        lastUIStamp = now
        DispatchQueue.main.async {
            self.magX = x; self.magY = y; self.magZ = z; self.magnitude = mag
        }
    }

    // MARK: Convenience
    var angleXY: Double { atan2(magY, magX) }
    var magnitudeXY: Double { sqrt(magX*magX + magY*magY) }
}
