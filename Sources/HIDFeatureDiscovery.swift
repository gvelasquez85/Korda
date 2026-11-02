import Foundation
// Original bounded HID++2 getter framing. No setters are representable.
enum KeyboardFeatureReply: Equatable { case payload([UInt8]); case error(UInt8) }
struct KeyboardFeatureQuery {
 let slot: UInt8
 let featureIndex: UInt8
 let function: UInt8
 let softwareID: UInt8
 let parameters: [UInt8]
 func permitsLegacyFallback(error:UInt8) -> Bool { featureIndex == 0 && function == 0 && parameters == [0x1b,0x04] && error == 9 }
 var packet: [UInt8]? {
  guard (1...6).contains(slot), (1...15).contains(softwareID) else { return nil }
  if featureIndex == 0 {
   guard function == 0, parameters == [0x1b,0x04] || parameters == [0x1b,0x00] else { return nil }
  } else {
   guard (function == 0 && parameters.isEmpty) || (function == 1 && parameters.count == 1) else { return nil }
  }
  return [0x10,slot,featureIndex,(function << 4) | softwareID] + parameters + Array(repeating:0,count:3-parameters.count)
 }
 func parse(_ bytes:[UInt8]) -> KeyboardFeatureReply? {
  guard packet != nil, (bytes.count == 7 && bytes.first == 0x10) || (bytes.count == 20 && bytes.first == 0x11), bytes[1] == slot else { return nil }
  let address = (function << 4) | softwareID
  if bytes[2] == 0x8f {
   guard bytes[3] == featureIndex, bytes[4] == address else { return nil }
   return .error(bytes[5])
  }
  guard bytes[2] == featureIndex, bytes[3] == address else { return nil }
  return .payload(Array(bytes.dropFirst(4)))
 }
}
struct KeyboardControlInfo: Equatable {
 let cid: UInt16
 let task: UInt16
 let flags: UInt16
 var isDivertable: Bool { flags & 0x20 != 0 }
 var consumerUsage: UInt32? { [UInt16(1):UInt32(233),2:234,3:226,4:205,5:181,6:182,10:402][task] }
 static func parseV4(_ payload:[UInt8]) -> KeyboardControlInfo? {
  guard payload.count >= 9 else { return nil }
  return KeyboardControlInfo(cid:UInt16(payload[0]) << 8 | UInt16(payload[1]),task:UInt16(payload[2]) << 8 | UInt16(payload[3]),flags:UInt16(payload[4]) | UInt16(payload[8]) << 8)
 }
 static func parseV1(_ payload:[UInt8]) -> KeyboardControlInfo? {
  guard payload.count >= 5 else { return nil }
  return KeyboardControlInfo(cid:UInt16(payload[0]) << 8 | UInt16(payload[1]),task:UInt16(payload[2]) << 8 | UInt16(payload[3]),flags:UInt16(payload[4]))
 }
}
struct KeyboardFeatureCatalog {
 let endpoint:String
 let slot:UInt8
 let wirelessID:UInt16
 let featureID:UInt16
 let featureIndex:UInt8
 let controls:[KeyboardControlInfo]
 func control(forUsage usage:UInt32) -> KeyboardControlInfo? {
  let matches = controls.filter{$0.consumerUsage == usage && $0.isDivertable}
  return featureID == 0x1b04 && featureIndex != 0 && matches.count == 1 ? matches[0] : nil
 }
}
