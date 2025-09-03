import SwiftUI
import UIKit   // UIPasteboard

struct ContentView: View {
    @StateObject private var mag = MagnetometerManager()

    // Live UTC clock
    @State private var utcNow = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Centralized toast
    @State private var showGlobalToast = false
    @State private var toastMessage = "Copied!"

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Title row: Icon + title (left) ... XYZ badge (right)
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image("Icon-DEV")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.secondary.opacity(0.4), lineWidth: 0.5)
                                )
                            Text("Mag Toolbox").monoTitle()
                        }
                        Spacer()
                        AxesBadge()
                    }

                    // Mode picker (Calibrated / Raw)
                    HStack {
                        Text("Mode").fontWeight(.semibold)
                        Picker("Mode", selection: $mag.mode) {
                            ForEach(MagnetometerManager.DataMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .mono10()
                    .padding(.horizontal, 2)

                    // ===== Field Visualizer ===== (no copy icon here)
                    MagVisualizer(
                        x: mag.magX, y: mag.magY, z: mag.magZ,
                        totalMag: mag.magnitude,
                        utcNow: utcNow
                    )
                    .mono10()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .modifier(CardBackground())

                    // ===== Field Strength + Compass =====
                    HStack(alignment: .center, spacing: 16) {

                        // Field Strength — title top-left + Copy button (trailing)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Field Strength").fontWeight(.semibold)
                                Spacer()
                                Button {
                                    copyFieldStrength(total: mag.magnitude, date: utcNow)
                                    triggerToast("Copied field strength")
                                } label: {
                                    Image(systemName: "doc.on.doc").imageScale(.medium)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Copy Field Strength")
                            }

                            Text(String(format: "%.1f µT", mag.magnitude))
                                .font(.system(size: 30, weight: .bold, design: .monospaced))

                            Text("Active: \(mag.activeMode.rawValue)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .mono10()
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .modifier(CardBackground())

                        // Compass — title top-left
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Compass").fontWeight(.semibold)

                            ZStack {
                                Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                                Image(systemName: "location.north.line.fill")
                                    .rotationEffect(.degrees(-mag.magneticHeading))
                                    .font(.system(size: 32, weight: .bold))
                            }
                            .frame(width: 84, height: 84)

                            let deg = mag.trueHeading ?? mag.magneticHeading
                            Text(directionLine(degrees: deg, label: mag.trueHeading != nil ? "True" : "Mag"))
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            if mag.headingAccuracy > 0 {
                                Text(String(format: "± %.0f°", mag.headingAccuracy))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .mono10()
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .modifier(CardBackground())
                    }

                    // ===== Field Components =====
                    FieldComponentsBox(
                        x: mag.magX, y: mag.magY, z: mag.magZ,
                        total: mag.magnitude, utcNow: utcNow
                    ) {
                        // onCopy callback: centralize toast here
                        triggerToast("Copied components")
                    }

                    // ===== Hint Cards =====
                    HintCards()
                        .mono10()
                        .padding(.top, 4)
                }
                .padding(16)
            }

            // Centralized toast at the very top
            GlobalToast(text: toastMessage, show: showGlobalToast)
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .allowsHitTesting(false)
        }
        .onReceive(timer) { now in
            utcNow = now
        }
        .onAppear {
            mag.start()
            mag.applyMode(mag.mode)
        }
        .onDisappear { mag.stop() }
        .onChange(of: mag.mode) { newMode in
            mag.applyMode(newMode)
        }
        .mono10()
    }

    // MARK: - Copy helpers
    private func copyFieldStrength(total: Double, date: Date) {
        let text = """
        Magnetometer — Field Strength
        UTC: \(utcTimeString(date))
        |B|: \(String(format: "%.3f", total)) µT
        """
        UIPasteboard.general.string = text
    }

    // MARK: - Central toast helper
    private func triggerToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showGlobalToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                showGlobalToast = false
            }
        }
    }

    // MARK: - Helpers
    private func directionLine(degrees: Double, label: String) -> String {
        let d = fmod(degrees + 360, 360)
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                    "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let idx = Int((d/22.5).rounded()) % dirs.count
        return String(format: "%@ %@ (%03.0f°)", label, dirs[idx], d)
    }

    private func utcTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return f.string(from: date)
    }
}

#Preview { ContentView() }

// ===========================================================
// Reuse components below
// ===========================================================

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        } else {
            content.background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
    }
}

// ===== Visualizer View (title + UTC time on the SAME line) =====
private struct MagVisualizer: View {
    let x: Double
    let y: Double
    let z: Double
    let totalMag: Double
    let utcNow: Date

    @State private var scaleMax: Double = 80.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header line: title (left) + UTC (right)
            HStack {
                Text("Field Visualizer").fontWeight(.semibold)
                Spacer()
                Text(utcTimeString(utcNow))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let size   = min(geo.size.width, 200)
                let radius = size * 0.42
                let xyMag  = magnitudeXY

                ZStack {
                    ForEach(1..<5) { i in
                        Circle()
                            .stroke(.secondary.opacity(i == 4 ? 0.35 : 0.18),
                                    lineWidth: i == 4 ? 1.2 : 0.8)
                            .frame(width: radius*2*CGFloat(Double(i)/4.0),
                                   height: radius*2*CGFloat(Double(i)/4.0))
                    }
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width/2 - radius, y: geo.size.height/2))
                        p.addLine(to: CGPoint(x: geo.size.width/2 + radius, y: geo.size.height/2))
                        p.move(to: CGPoint(x: geo.size.width/2, y: geo.size.height/2 - radius))
                        p.addLine(to: CGPoint(x: geo.size.width/2, y: geo.size.height/2 + radius))
                    }
                    .stroke(.secondary.opacity(0.2), lineWidth: 0.6)

                    Arrow(
                        start: CGPoint(x: geo.size.width/2, y: geo.size.height/2),
                        angle: atan2(y, x),
                        length: CGFloat(min(xyMag, scaleMax) / scaleMax) * radius
                    )
                    .stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                // Telemetry at the bottom
                .overlay(alignment: .bottom) {
                    VStack(spacing: 2) {
                        Text(String(format: "XY: %.1f µT", xyMag))
                        Text(String(format: "Z: %+.1f µT", z))
                        Text(String(format: "Total: %.1f µT", totalMag))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }
                .frame(height: size)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 200)
        }
        .onChange(of: totalMag) { _ in updateScale() }
        .onChange(of: x) { _ in updateScale() }
        .onChange(of: y) { _ in updateScale() }
        .onChange(of: z) { _ in updateScale() }
    }

    private var magnitudeXY: Double { sqrt(x*x + y*y) }

    private func updateScale() {
        let biggest = max(magnitudeXY, abs(z), totalMag)
        let candidate = min(200.0, max(20.0, biggest * 1.3))
        scaleMax = 0.9 * scaleMax + 0.1 * candidate
    }

    private func utcTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return f.string(from: date)
    }
}

private struct Arrow: Shape {
    let start: CGPoint
    let angle: Double
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let shaftLen: CGFloat = max(0, length - 10)
        var local = Path()
        local.move(to: .zero)
        local.addLine(to: CGPoint(x: 0, y: -shaftLen))
        local.move(to: CGPoint(x: 0, y: -length))
        local.addLine(to: CGPoint(x: -6, y: -length + 10))
        local.move(to: CGPoint(x: 0, y: -length))
        local.addLine(to: CGPoint(x: 6, y: -length + 10))

        let transform = CGAffineTransform(translationX: start.x, y: start.y)
            .rotated(by: angle - .pi/2)
        p.addPath(local.applying(transform))
        return p
    }
}

private struct AxesBadge: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let c = CGPoint(x: w*0.45, y: h*0.6)
            let L = min(w, h) * 0.38

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.12))

                Path { p in
                    p.move(to: c); p.addLine(to: CGPoint(x: c.x + L, y: c.y))
                }.stroke(.red, lineWidth: 2)
                Text("X")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                    .position(x: c.x + L + 10, y: c.y)

                Path { p in
                    p.move(to: c); p.addLine(to: CGPoint(x: c.x, y: c.y - L))
                }.stroke(.green, lineWidth: 2)
                Text("Y")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .position(x: c.x, y: c.y - L - 8)

                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .position(c)
                Text("Z")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
                    .position(x: c.x + 12, y: c.y + 12)
            }
        }
        .frame(width: 84, height: 44)
        .modifier(CardBackground())
    }
}

// ===== Field Components (µT) box =====
private struct FieldComponentsBox: View {
    let x: Double
    let y: Double
    let z: Double
    let total: Double   // |B|
    let utcNow: Date
    let onCopied: () -> Void   // central toast trigger

    private var span: Double {
        max(100, min(1000, max(abs(x), abs(y), abs(z), total) * 1.5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Field Components (uT)")
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    copyComponents()
                    onCopied()
                } label: {
                    Image(systemName: "doc.on.doc").imageScale(.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy Field Components")
            }

            componentRow(label: "X", value: x)
            componentRow(label: "Y", value: y)
            componentRow(label: "Z", value: z)

            DisclosureGroup("▸ |B|:") {
                HStack(spacing: 12) {
                    bar(value: total)
                    Text(String(format: "%+.2f", total))
                        .font(.system(.title3, design: .monospaced)).monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(colorFor(uT: total))
                }
                .padding(.top, 4)
            }
            .tint(.secondary)
        }
        .mono10()
        .padding()
        .frame(maxWidth: .infinity)
        .modifier(CardBackground())
    }

    private func componentRow(label: String, value: Double) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .fontWeight(.semibold)
                .frame(width: 16, alignment: .leading)

            bar(value: value)

            Text(String(format: "%+.2f", value))
                .font(.system(.title3, design: .monospaced)).monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(colorFor(uT: value))
        }
    }

    private func bar(value: Double) -> some View {
        let clamped = max(-span, min(span, value))
        let frac    = CGFloat(abs(clamped) / span)

        return ZStack {
            RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.15))
            GeometryReader { g in
                let W = g.size.width
                let H = g.size.height
                let half = W / 2
                let w = max(2, half * frac)
                let startX = (value >= 0) ? half : (half - w)

                RoundedRectangle(cornerRadius: 5)
                    .fill(colorFor(uT: value).opacity(0.85))
                    .frame(width: w, height: H)
                    .position(x: startX + w/2, y: H/2)
            }.clipped()
            Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1)
        }
        .frame(height: 10)
    }

    private func copyComponents() {
        let f = DateFormatter()
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        let timestamp = f.string(from: utcNow)

        let text = """
        Magnetometer — Field Components
        UTC: \(timestamp)
        |B|: \(String(format: "%.3f", total)) µT
        X: \(String(format: "%+.3f", x)) µT
        Y: \(String(format: "%+.3f", y)) µT
        Z: \(String(format: "%+.3f", z)) µT
        """
        UIPasteboard.general.string = text
    }
}

// ---------- Shared bits ----------
private func colorFor(uT: Double) -> Color {
    let v = abs(uT)
    if v >= 1000 { return .red }
    if v >= 100  { return .orange }
    return .primary
}

private struct GlobalToast: View {
    let text: String
    let show: Bool

    var body: some View {
        Group {
            if show {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .shadow(radius: 2, y: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// ===== Hint Cards =====
private struct HintCards: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hints").fontWeight(.semibold)

            DisclosureGroup("▸ Calibrated vs Raw") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Calibrated: Uses iOS Core Motion (Apple’s sensor-fusion framework) to correct bias/scale from the raw magnetometer and combine it with gyro/accelerometer for a steadier reading.")
                    Text("• Raw: Direct sensor output without bias/soft-iron correction. More sensitive to nearby metal, wiring, and magnets.")
                    Text("• Expect Raw to vary more and read higher near electronics; Calibrated is generally smoother and closer to the Earth field.")
                }
                .padding(.top, 4)
            }
            .tint(.secondary)

            DisclosureGroup("▸ How and why the magnetometer works") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Measures the 3-axis magnetic field (X, Y, Z) in microtesla (µT). Total |B| = √(X²+Y²+Z²).")
                    Text("• Why it matters: Earth’s magnetic field gives an absolute reference for yaw (heading). Gyros drift; magnetometers anchor heading, especially when GPS heading is unreliable at low speeds.")
                    Text("• The field isn’t flat: lines dip into the Earth. Z-component shows inclination; horizontal components point toward magnetic north (which differs from true north by local declination).")
                }
                .padding(.top, 4)
            }
            .tint(.secondary)

            DisclosureGroup("▸ Calibration tips (drones & devices)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Perform the platform’s compass/magnetometer calibration routine outdoors, away from concrete, vehicles, rebar, and power lines.")
                    Text("• Move through figure-8s and rotate slowly on all axes; follow your flight controller or device prompts until success.")
                    Text("• Mount the mag far from ESCs, motors, and high-current wires; twist power leads and add ferrites to reduce noise. Consider an external magnetometer on a mast/boom.")
                    Text("• Re-calibrate after frame changes, wiring reroutes, or if heading drifts. Verify magnetic declination is set/updated in your controller software.")
                }
                .padding(.top, 4)
            }
            .tint(.secondary)

            DisclosureGroup("▸ Common magnetometer issues") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Hard/soft-iron interference from screws, frames, speakers, or magnets (including phone/tablet cases).")
                    Text("• Electrical noise/saturation from ESCs and power cables; indoor metal structures causing inconsistent headings.")
                    Text("• Temperature drift or mounting orientation mismatch vs. the controller’s assumed axes.")
                }
                .padding(.top, 4)
            }
            .tint(.secondary)

            DisclosureGroup("▸ Fixes and mitigations") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Relocate or elevate the sensor; use an external compass module away from motors/ESCs.")
                    Text("• Twist high-current wires, add ferrite rings, keep magnets out of mounts/cases; replace steel hardware with non-magnetic where feasible.")
                    Text("• Re-run calibration after any hardware changes; set correct magnetic declination; ensure axis orientation matches the controller configuration.")
                    Text("• If saturated, increase distance from sources or add shielding (e.g., mu-metal) judiciously; then re-calibrate.")
                }
                .padding(.top, 4)
            }
            .tint(.secondary)

            DisclosureGroup("▸ Units & thresholds") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Readings are in µT. Typical Earth field is about 25–65 µT depending on location.")
                    Text("• In this app: ≥100 µT shows orange, ≥1000 µT shows red as high-field indicators.")
                }
                .padding(.top, 4)
            }
            .tint(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .modifier(CardBackground())
    }
}
