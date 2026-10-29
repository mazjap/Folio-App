import Foundation

extension Date {
    // MARK: - Functions
    
    /// Midnight UTC on the calendar day this date falls on in `timeZone`.
    ///
    /// Date-only values (like a privacy policy's `lastUpdated`, `yyyy-MM-dd`) are kept as midnight UTC and shown in UTC, so the day picked is the day saved wherever the device is.
    func calendarDay(in timeZone: TimeZone = .current) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        return utc.date(from: local.dateComponents([.year, .month, .day], from: self)) ?? self
    }
}
