import Foundation

public enum Formatting {
    public static func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var size = Double(value)
        var index = 0
        while size >= 1024, index < units.count - 1 {
            size /= 1024
            index += 1
        }
        return index == 0 ? "\(Int(size)) B" : String(format: "%.1f %@", size, units[index])
    }

    public static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let (hours, rest) = total.quotientAndRemainder(dividingBy: 3600)
        let (minutes, secs) = rest.quotientAndRemainder(dividingBy: 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    public static func speed(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return "—" }
        return String(format: "%.1f MiB/s", bytesPerSecond / 1024 / 1024)
    }
}
