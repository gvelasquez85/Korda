// Original decoder based on report ID 2 in this Mac's observed receiver descriptor.
// Contract: exactly seven payload bytes: 16 button bits, 24 motion bits,
// eight wheel bits and eight pan bits. Only the first two bytes are inspected.
// A caller must explicitly state whether its buffer includes the report ID.
// No keyboard, vendor, movement, wheel, or pan interpretation is performed.
enum MouseReportBufferFormat { case payloadOnly, reportIDPrefixed }
struct MouseButtonChange: Equatable {
 let button: UInt8
 let isDown: Bool
}
struct MouseReportResult: Equatable {
 let extraButtonsMask: UInt16
 let changes: [MouseButtonChange]
}
struct MouseReportDecoder {
 static func decode(reportID: UInt32, data: [UInt8], format: MouseReportBufferFormat, previousExtraButtonsMask: UInt16) -> MouseReportResult? {
  guard reportID == 2 else { return nil }
  let offset: Int
  switch format {
  case .payloadOnly:
   guard data.count == 7 else { return nil }
   offset = 0
  case .reportIDPrefixed:
   guard data.count == 8, data[0] == 2 else { return nil }
   offset = 1
  }
  let current = (UInt16(data[offset]) | UInt16(data[offset + 1]) << 8) & 0xfffc
  let changed = current ^ (previousExtraButtonsMask & 0xfffc)
  let changes = (3...16).compactMap { button -> MouseButtonChange? in
   let bit = UInt16(1) << (button - 1)
   guard changed & bit != 0 else { return nil }
   return MouseButtonChange(button: UInt8(button), isDown: current & bit != 0)
  }
  return MouseReportResult(extraButtonsMask: current, changes: changes)
 }
}
