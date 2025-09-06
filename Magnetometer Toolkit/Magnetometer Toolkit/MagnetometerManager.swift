import Foundation
import CoreMotion
import CoreLocation

final class MagnetometerManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    enum DataMode: String, CaseIterable, Identifiable {
        case calibrated = "Calibrated"
        case raw = "Raw"
        var id: String { rawValue }
    }

    @Published var mode: DataMode = .calibrated
    @Published private(set) var activeMode: DataMode = .calibrated

    @Published var magX: Double = 0
    @Published var magY: Double = 0
    @Published var magZ: Double = 0
    @Published var magnitude: Double = 0

    @Published var magneticHeading: Double = 0
    @Published var trueHeading: Double? = nil
    @Published var headingAccuracy: Double = 0

    @Published var locationAuthStatus: CLAuthorizationStatus = .notDetermined
    @Published var headingAvailable: Bool = CLLocationManager.headingAvailable()

    @Published var calibrationAccuracy: CMMagneticFieldCalibrationAccuracy = .uncalibrated
    @Published var isSwitchingMode: Bool = false

    private let motion = CMMotionManager()
    private let loc = CLLocationManager()

    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "MagnetometerManager.motion"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private let serial = DispatchQueue(label: "MagnetometerManager.serial")

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
        applyMode(mode)
    }

    func stop() {
        loc.stopUpdatingHeading()
        stopMagStreams()
    }

    // MARK: Mode switching (debounced & serialized)
    func applyMode(_ newMode: DataMode) {
        guard !isSwitchingMode else { return }
        DispatchQueue.main.async { self.isSwitchingMode = true }
        serial.async { [weak self] in
            guard let self else { return }
            self.stopMagStreams()
            switch newMode {
            case .calibrated:
                if self.motion.isDeviceMotionAvailable {
                    self.startCalibrated()
                    DispatchQueue.main.async { self.activeMode = .calibrated }
                } else {
                    self.startRaw()
                    DispatchQueue.main.async { self.activeMode = .raw }
                }
            case .raw:
                self.startRaw()
                DispatchQueue.main.async { self.activeMode = .raw }
            }
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
        DispatchQueue.main.async { self.locationAuthStatus = manager.authorizationStatus }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            startHeading()
        } else {
            loc.stopUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Core Location delegate callbacks are on main by default, but keep explicit
        DispatchQueue.main.async {
            self.magneticHeading = fmod(newHeading.magneticHeading + 360, 360)
            self.trueHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil
            self.headingAccuracy = newHeading.headingAccuracy
        }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }

    // MARK: Magnetics
    private func startCalibrated() {
        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: motionQueue) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let f = dm.magneticField
            let x = f.field.x, y = f.field.y, z = f.field.z
            let mag = sqrt(x*x + y*y + z*z)

            // publish calibration accuracy on main
            DispatchQueue.main.async { self.calibrationAccuracy = f.accuracy }
            self.dispatchUI(x: x, y: y, z: z, mag: mag)
        }
    }

    private func startRaw() {
        guard motion.isMagnetometerAvailable else { return }
        motion.magnetometerUpdateInterval = 1.0 / 20.0
        motion.startMagnetometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let m = data?.magneticField else { return }
            let x = m.x, y = m.y, z = m.z
            let mag = sqrt(x*x + y*y + z*z)
            self.dispatchUI(x: x, y: y, z: z, mag: mag)
        }
    }

    // Throttle main-thread publishes to ~20 Hz
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
