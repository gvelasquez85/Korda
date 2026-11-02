import Foundation

// Original framing for Unifying c52b receiver management. The caller must
// enforce transport compatibility and explicit user confirmation before I/O.
enum ReceiverManagementReply: Equatable {
 case accepted
 case rejected(UInt8)
}
enum ReceiverManagementCommand: Equatable {
 case openPairing
 case closePairing
 case unpair(slot: UInt8)
 var slot: UInt8? { if case let .unpair(slot) = self { return slot }; return nil }
 var label: String {
  switch self {
  case .openPairing: return "Abrir emparejamiento"
  case .closePairing: return "Cerrar emparejamiento"
  case .unpair(let slot): return "Desvincular posición \(slot)"
  }
 }
 var packet: [UInt8]? {
  switch self {
  case .openPairing: return [0x10,0xff,0x80,0xb2,0x01,0x00,0x3c]
  case .closePairing: return [0x10,0xff,0x80,0xb2,0x02,0x00,0x00]
  case .unpair(let slot):
   guard (1...6).contains(slot) else { return nil }
   return [0x10,0xff,0x80,0xb2,0x03,slot,0x00]
  }
 }
 func parseReply(_ bytes: [UInt8]) -> ReceiverManagementReply? {
  guard packet != nil, bytes.count == 7, bytes[0] == 0x10, bytes[1] == 0xff else { return nil }
  if bytes[2] == 0x7f, bytes[3] == 0x80, bytes[4] == 0xb2 { return .rejected(bytes[5]) }
  guard bytes[2] == 0x80, bytes[3] == 0xb2 else { return nil }
  return .accepted
 }
}
struct ReceiverPairingNotification: Equatable {
 let open: Bool
 let error: UInt8
 static func parse(_ bytes: [UInt8]) -> ReceiverPairingNotification? {
  guard bytes.count == 7, bytes[0] == 0x10, bytes[1] == 0xff, bytes[2] == 0x4a,
        bytes[3] <= 1 else { return nil }
  return ReceiverPairingNotification(open:bytes[3] == 1,error:bytes[4])
 }
}
