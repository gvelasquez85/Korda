// Original passive decoder, from the receiver descriptor and installed driver's
// verified static paths documented in docs/m570-driver-path.md and
// docs/m570-client-route.md. These patterns do NOT prove a slot's model identity.
enum ReceiverReportBufferFormat { case payloadOnly, reportIDPrefixed }
struct ReceiverButtonResult: Equatable {
 let slot: UInt8
 let extraButtonsMask: UInt16
 let changes: [MouseButtonChange]
}
struct ReceiverIdentity: Equatable { let slot: UInt8; let wirelessID: UInt16 }
struct ReceiverReportDecoder {
 private static func normalize(reportID: UInt32, expectedID: UInt8, count: Int, data: [UInt8], format: ReceiverReportBufferFormat) -> [UInt8]? {
  guard reportID == UInt32(expectedID) else { return nil }
  switch format {
  case .payloadOnly:
   guard data.count == count - 1 else { return nil }
   return [expectedID] + data
  case .reportIDPrefixed:
   guard data.count == count, data[0] == expectedID else { return nil }
   return data
  }
 }
 private static func result(slot: UInt8, mask: UInt16, previousMasks: [UInt8:UInt16]) -> ReceiverButtonResult {
  let extra = mask & 0xfffc
  let changed = extra ^ ((previousMasks[slot] ?? 0) & 0xfffc)
  let changes = (3...16).compactMap { button -> MouseButtonChange? in
   let bit = UInt16(1) << (button - 1)
   return changed & bit == 0 ? nil : MouseButtonChange(button: UInt8(button), isDown: extra & bit != 0)
  }
  return ReceiverButtonResult(slot:slot,extraButtonsMask:extra,changes:changes)
 }
 static func decodeM570Identity(reportID: UInt32, data: [UInt8], format: ReceiverReportBufferFormat) -> ReceiverIdentity? {
  guard reportID == 0x20 || reportID == 0x21,
        let packet = normalize(reportID:reportID,expectedID:UInt8(reportID),count:reportID == 0x20 ? 15 : 32,data:data,format:format),
        (1...6).contains(packet[1]), packet[2] == 0x41, packet[3] & 2 == 0,
        packet[4] == 0x28, packet[5] == 0x10 else { return nil }
  return ReceiverIdentity(slot:packet[1],wirelessID:0x1028)
 }
 static func decodeDJMouse(reportID: UInt32, data: [UInt8], format: ReceiverReportBufferFormat, previousMasks: [UInt8:UInt16]) -> ReceiverButtonResult? {
  guard let packet = normalize(reportID:reportID,expectedID:0x20,count:15,data:data,format:format),
        packet[2] == 2, (1...6).contains(packet[1]) else { return nil }
  // Only the mouse report's two button bytes are read. The ten remaining bytes
  // (coordinates/wheels/reserved) are never interpreted, returned or logged.
  return result(slot:packet[1],mask:UInt16(packet[3]) | UInt16(packet[4]) << 8,previousMasks:previousMasks)
 }
 static func decodeSynthetic1B04(reportID: UInt32, data: [UInt8], format: ReceiverReportBufferFormat, previousMasks: [UInt8:UInt16]) -> ReceiverButtonResult? {
  guard let packet = normalize(reportID:reportID,expectedID:0x11,count:20,data:data,format:format),
        (1...6).contains(packet[1]), packet[2] == 6, packet[3] == 0,
        packet[12...19].allSatisfy({ $0 == 0 }) else { return nil }
  var mask: UInt16 = 0
  for index in stride(from:4,to:12,by:2) {
   let cid = UInt16(packet[index]) << 8 | UInt16(packet[index + 1])
   switch cid {
   case 0, 0x50, 0x51: break
   case 0x52: mask |= 4
   case 0x53: mask |= 8
   case 0x56: mask |= 16
   default: return nil
   }
  }
  return result(slot:packet[1],mask:mask,previousMasks:previousMasks)
 }
}
