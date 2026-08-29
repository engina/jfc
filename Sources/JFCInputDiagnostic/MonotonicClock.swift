import Darwin
import Foundation

enum MonotonicClock {
  private static let timebase: mach_timebase_info_data_t = {
    var value = mach_timebase_info_data_t()
    mach_timebase_info(&value)
    return value
  }()

  static func now() -> UInt64 {
    mach_absolute_time()
  }

  static func nanoseconds(_ absoluteTime: UInt64) -> UInt64 {
    let value = Double(absoluteTime) * Double(timebase.numer) / Double(timebase.denom)
    return UInt64(value.rounded())
  }
}
