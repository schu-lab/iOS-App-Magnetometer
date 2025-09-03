import SwiftUI

struct ContentView: View {
    @StateObject private var mag = MagnetometerManager()

    var body: some View {
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

                        Text("Mag Toolbox")
                            .monoTitle()
                    }
                    Spacer()
                    AxesBadge() // tiny RGB XYZ device axes indicator
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

                // ===== Field Visualizer (circles unchanged; telemetry at bottom) =====
                MagVisualizer(x: mag.magX, y: mag.magY, z: mag.magZ, totalMag: mag.magnitude)
                    .mono10()
                    .padding()
                    // Frame first, then background to keep visual width fixed
                    .frame(maxWidth: .infinity)
                    .modifier(CardBackground())

                // ===== Field Strength + Compass (same width & larger size) =====
                HStack(alignment: .center, spacing: 16) {

                    // Field Strength card
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Field Strength").fontWeight(.semibold)
                        Text(String(format: "%.1f µT", mag.magnitude))
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                        Text("Active: \(mag.activeMode.rawValue)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .mono10()
                    .padding()
                    // Fix card’s visual size before adding background (prevents width jitter)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .modifier(CardBackground())

                    // Compass card — fixed visual width; Direction + Bearing below
                    VStack(alignment: .leading, spacing: 10) {
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
                    // Fix card’s visual size before adding background (prevents width jitter)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .modifier(CardBackground())
                }

                // ===== Field Components (µT) =====
                FieldComponentsBox(
                    x: mag.magX,
                    y: mag.magY,
                    z: mag.magZ,
                    total: mag.magnitude
                )

                // ===== Hint Cards =====
                HintCards()
                    .mono10()
                    .padding(.top, 4)
            }
            .padding(16)
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

    // MARK: - Helpers
    private func directionLine(degrees: Double, label: String) -> String {
        let d = fmod(degrees + 360, 360)
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                    "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let idx = Int((d/22.5).rounded()) % dirs.count
        // Keep a compact line; remove “Heading:” to avoid width changes
        return String(format: "%@ %@ (%03.0f°)", label, dirs[idx], d)
    }
}

#Preview { ContentView() }

/// Card background that works on iOS 14+ (falls back if materials unavailable)
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

// ===== Visualizer View (auto-range; UI output at bottom) =====
private struct MagVisualizer: View {
    let x: Double
    let y: Double
    let z: Double
    let totalMag: Double

    @State private var scaleMax: Double = 80.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Field Visualizer").fontWeight(.semibold)

            GeometryReader { geo in
                let size   = min(geo.size.width, 200)   // slight shrink for spacing
                let radius = size * 0.42
                let xyMag  = magnitudeXY

                ZStack {
                    // Concentric rings (same locations)
                    ForEach(1..<5) { i in
                        Circle()
                            .stroke(.secondary.opacity(i == 4 ? 0.35 : 0.18), lineWidth: i == 4 ? 1.2 : 0.8)
                            .frame(width: radius*2*CGFloat(Double(i)/4.0),
                                   height: radius*2*CGFloat(Double(i)/4.0))
                    }

                    // Crosshair
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width/2 - radius, y: geo.size.height/2))
                        p.addLine(to: CGPoint(x: geo.size.width/2 + radius, y: geo.size.height/2))
                        p.move(to: CGPoint(x: geo.size.width/2, y: geo.size.height/2 - radius))
                        p.addLine(to: CGPoint(x: geo.size.width/2, y: geo.size.height/2 + radius))
                    }
                    .stroke(.secondary.opacity(0.2), lineWidth: 0.6)

                    // XY arrow
                    Arrow(
                        start: CGPoint(x: geo.size.width/2, y: geo.size.height/2),
                        angle: atan2(y, x),
                        length: CGFloat(min(xyMag, scaleMax) / scaleMax) * radius
                    )
                    .stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                // Telemetry at the BOTTOM: XY, Z, Total
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
        // Smooth follow (EMA)
        scaleMax = 0.9 * scaleMax + 0.1 * candidate
    }
}

// Simple arrow shape pointing in +Y by default; rotation applied via `angle`
private struct Arrow: Shape {
    let start: CGPoint
    let angle: Double    // radians, 0 = +X, pi/2 = +Y
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

/// Tiny RGB XYZ badge that matches iPhone device axes (portrait).
/// X = red → right, Y = green ↑ top, Z = blue • out of screen.
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

                // X (red, →)
                Path { p in
                    p.move(to: c); p.addLine(to: CGPoint(x: c.x + L, y: c.y))
                }.stroke(.red, lineWidth: 2)
                Text("X")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                    .position(x: c.x + L + 10, y: c.y)

                // Y (green, ↑)
                Path { p in
                    p.move(to: c); p.addLine(to: CGPoint(x: c.x, y: c.y - L))
                }.stroke(.green, lineWidth: 2)
                Text("Y")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .position(x: c.x, y: c.y - L - 8)

                // Z (blue, dot at origin)
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

    // Symmetric visual range around 0 (auto-expands up to 1000 µT)
    private var span: Double {
        max(100, min(1000, max(abs(x), abs(y), abs(z), total) * 1.5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Field Components (uT)")
                .fontWeight(.semibold)

            componentRow(label: "X", value: x)
            componentRow(label: "Y", value: y)
            componentRow(label: "Z", value: z)

            // |B| disclosure
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

    // One row like your image: label, bar, value
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

    // Center-zero bar with thin middle hairline
    private func bar(value: Double) -> some View {
        let clamped = max(-span, min(span, value))
        let frac    = CGFloat(abs(clamped) / span)

        return ZStack {
            // track
            RoundedRectangle(cornerRadius: 5)
                .fill(.secondary.opacity(0.15))

            // fill from center → toward sign of value
            GeometryReader { g in
                let W = g.size.width
                let H = g.size.height
                let half = W / 2
                let w = max(2, half * frac)           // width of fill
                let startX = (value >= 0) ? half : (half - w)

                RoundedRectangle(cornerRadius: 5)
                    .fill(colorFor(uT: value).opacity(0.85))
                    .frame(width: w, height: H)
                    .position(x: startX + w/2, y: H/2)
            }
            .clipped()

            // center hairline
            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(width: 1)
        }
        .frame(height: 10)
    }
}

// Threshold coloring (abs value): ≥100 → orange, ≥1000 → red
private func colorFor(uT: Double) -> Color {
    let v = abs(uT)
    if v >= 1000 { return .red }
    if v >= 100  { return .orange }
    return .primary
}

// ===== Hint Cards =====
private struct HintCards: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hints").fontWeight(.semibold)

            // Calibrated vs Raw
            DisclosureGroup("▸ Calibrated vs Raw") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Calibrated uses Core Motion’s fused magnetic field with bias correction (helps remove hard/soft iron).")
                    Text("• Raw uses the magnetometer directly; values include local interference from the device and environment.")
                    Text("• Expect Raw to be noisier and higher magnitude near metal/electronics; Calibrated is generally steadier.")
                }
                .padding(.top, 4)
            }
            .tint(.secondary)

            // Magnetometer functionality
            DisclosureGroup("▸ How the magnetometer works") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• The sensor measures the 3-axis field vector (X, Y, Z) in microtesla (µT).")
                    Text("• Total strength |B| = √(X² + Y² + Z²).")
                    Text("• Heading uses both magnetometer and other sensors; accuracy can drop indoors or near ferrous objects.")
                }
                .padding(.top, 4)
            }
            .tint(.secondary)

            // Calibration tips
            DisclosureGroup("▸ Calibration tips") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Slowly move the phone in a figure-8 and rotate through different orientations.")
                    Text("• Keep distance from magnets, speakers, cables, and large metal surfaces.")
                    Text("• If accuracy degrades, re-calibrate and avoid cases with magnetic latches.")
                }
                .padding(.top, 4)
            }
            .tint(.secondary)

            // Units & thresholds
            DisclosureGroup("▸ Units & thresholds") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Display is in microtesla (µT). Typical Earth field is ~25–65 µT depending on location.")
                    Text("• In this app: ≥100 µT shows orange, ≥1000 µT shows red as a high field indicator.")
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
