import Foundation

/// Parses a 12-hour clock time such as "9:30 AM", "09:30AM" or "12:05 pm" into total minutes
/// since midnight (0-1439). Hours must be 1-12 and minutes 0-59; anything else returns nil.
///
/// This is deliberately strict. DateFormatter is lenient and accepts out-of-range values
/// ("25:00 AM", "9:60 AM") differently depending on the system, so it is not used here.
func parseTimeHMMA(timeString: String) -> Int? {
  let trimmedTime = timeString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

  let isPM: Bool
  if trimmedTime.hasSuffix("AM") {
    isPM = false
  } else if trimmedTime.hasSuffix("PM") {
    isPM = true
  } else {
    return nil
  }

  let clock = trimmedTime.dropLast(2).trimmingCharacters(in: .whitespaces)
  let fields = clock.split(separator: ":", omittingEmptySubsequences: false)
  guard fields.count == 2,
    (1...2).contains(fields[0].count), fields[1].count == 2,
    fields.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
    let hour12 = Int(fields[0]), (1...12).contains(hour12),
    let minute = Int(fields[1]), (0...59).contains(minute)
  else {
    return nil
  }

  let hour24 = hour12 % 12 + (isPM ? 12 : 0)
  return hour24 * 60 + minute
}
