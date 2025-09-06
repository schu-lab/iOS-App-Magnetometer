//  Maff.swift
//  Magnetometer Toolkit

import Foundation

enum Maff {
    /// Reusable, cached UTC formatter (DateFormatter is not thread-safe;
    /// we only use it from the main/UI thread in this app).
    static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return f
    }()

    /// Convenience helper
    static func utcString(_ date: Date) -> String {
        utcFormatter.string(from: date)
    }
}
