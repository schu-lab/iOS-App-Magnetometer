//
//  MagnetometerManager.swift
//  Magnetometer Toolkit
//
//  Created by Simon Chu on 9/2/25.
//
import Foundation
import CoreMotion
import CoreLocation

/// Magnetometer + heading manager with switchable RAW / CALIBRATED modes.
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

    private let motion = CMMotionManager()
    private let loc = CLLocationManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "MagnetometerManager.motion"
        q.qualityOfService = .userInitiated
        return q
    }()

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

    // MARK: Mode switching
    func applyMode(_ newMode: DataMode) {
        stopMagStreams()
        switch newMode {
        case .calibrated:
            if motion.isDeviceMotionAvailable {
                startCalibrated()
                activeMode = .calibrated
            } else {
                startRaw()
                activeMode = .raw
            }
        case .raw:
            startRaw()
            activeMode = .raw
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
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let f = dm.magneticField
            self.calibrationAccuracy = f.accuracy
            let x = f.field.x, y = f.field.y, z = f.field.z
            let mag = sqrt(x*x + y*y + z*z)
            DispatchQueue.main.async {
                self.magX = x; self.magY = y; self.magZ = z; self.magnitude = mag
            }
        }
    }

    /// RAW magnetics via CMMotionManager (uncorrected µT; includes hard/soft-iron effects)
    private func startRaw() {
        guard motion.isMagnetometerAvailable else { return }
        motion.magnetometerUpdateInterval = 1.0 / 30.0
        motion.startMagnetometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let m = data?.magneticField else { return }
            let x = m.x, y = m.y, z = m.z
            let mag = sqrt(x*x + y*y + z*z)
            DispatchQueue.main.async {
                self.magX = x; self.magY = y; self.magZ = z; self.magnitude = mag
            }
        }
    }

    // MARK: Convenience
    var angleXY: Double { atan2(magY, magX) }
    var magnitudeXY: Double { sqrt(magX*magX + magY*magY) }

    func cardinal(from degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                    "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let idx = Int((degrees/22.5).rounded()) % dirs.count
        return dirs[idx]
    }
}
