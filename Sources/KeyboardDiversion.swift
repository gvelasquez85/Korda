import Foundation
struct KeyboardReportingSnapshot: Equatable {
 let cid: UInt16
 let flags: UInt16
 let mappedCID: UInt16
 static func parse(_ bytes:[UInt8],expectedCID:UInt16) -> Self? {
  guard bytes.count >= 5 else { return nil }
  let cid = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
  guard cid == expectedCID else { return nil }
  return Self(cid:cid,flags:UInt16(bytes[2]) | (bytes.count > 5 ? UInt16(bytes[5]) << 8 : 0),mappedCID:UInt16(bytes[3]) << 8 | UInt16(bytes[4]))
 }
}
enum KeyboardDivertedButtons {
 static func decode(_ bytes:[UInt8],slot:UInt8,featureIndex:UInt8) -> Set<UInt16>? {
  guard bytes.count == 20,bytes[0] == 0x11,bytes[1] == slot,bytes[2] == featureIndex,bytes[3] == 0,bytes[12...].allSatisfy({$0 == 0}) else { return nil }
  var result = Set<UInt16>()
  for i in stride(from:4,to:12,by:2) {
   let cid = UInt16(bytes[i]) << 8 | UInt16(bytes[i+1])
   if cid != 0 && !result.insert(cid).inserted { return nil }
  }
  return result
 }
}
struct KeyboardDiversionLease: Equatable {
 let endpoint:String
 let slot:UInt8
 let wirelessID:UInt16
 let featureIndex:UInt8
 let featureID:UInt16 = 0x1b04
 let cid:UInt16
 let capabilityFlags:UInt16
 var isEligible:Bool { !endpoint.isEmpty && (1...6).contains(slot) && wirelessID != 0 && wirelessID != 0xffff && featureID == 0x1b04 && featureIndex != 0 && cid != 0 && capabilityFlags & 0x20 != 0 }
}
enum KeyboardDiversionPhase: Equatable { case awaitingBaseline, ready, enableUncertain, active, restoreUncertain, restored, conflict }
struct KeyboardDiversionPlanner {
 let lease:KeyboardDiversionLease
 private(set) var phase:KeyboardDiversionPhase = .awaitingBaseline
 private(set) var baseline:KeyboardReportingSnapshot?
 private(set) var restorationRequired = false
 mutating func acceptBaseline(_ snapshot:KeyboardReportingSnapshot) -> Bool {
  guard phase == .awaitingBaseline, lease.isEligible, snapshot.cid == lease.cid, snapshot.flags & 5 == 0 else { return false }
  baseline = snapshot; phase = .ready; return true
 }
 private func packet(divert:Bool,softwareID:UInt8) -> [UInt8]? {
  guard lease.isEligible,(1...15).contains(softwareID) else { return nil }
  return [0x11,lease.slot,lease.featureIndex,0x30 | softwareID,UInt8(lease.cid >> 8),UInt8(lease.cid & 255),divert ? 3 : 2,0,0] + Array(repeating:0,count:11)
 }
 mutating func prepareEnable(softwareID:UInt8) -> [UInt8]? {
  guard phase == .ready, let packet = packet(divert:true,softwareID:softwareID) else { return nil }
  phase = .enableUncertain; restorationRequired = true; return packet
 }
 // ACK/error/timeout never establishes activation nor releases uncertain ownership.
 mutating func acknowledgeWrite() {}
 mutating func writeTimedOut() {}
 mutating func observeEnabled(_ snapshot:KeyboardReportingSnapshot) -> Bool {
  guard phase == .enableUncertain, let baseline, snapshot.cid == lease.cid else { return false }
  guard snapshot.flags == baseline.flags | 1, snapshot.mappedCID == baseline.mappedCID else { phase = .conflict; return false }
  phase = .active; return true
 }
 mutating func prepareRestore(current:KeyboardReportingSnapshot,softwareID:UInt8) -> [UInt8]? {
  guard restorationRequired, let baseline, current.cid == lease.cid else { return nil }
  // Already restored after an uncertain write: observation resolves ownership.
  if current == baseline { restorationRequired = false; phase = .restored; return nil }
  guard current.flags == baseline.flags | 1,current.mappedCID == baseline.mappedCID else { phase = .conflict; return nil }
  guard let packet = packet(divert:false,softwareID:softwareID) else { return nil }
  phase = .restoreUncertain; return packet
 }
 mutating func observeRestored(_ snapshot:KeyboardReportingSnapshot) -> Bool {
  guard restorationRequired, let baseline, snapshot == baseline else { return false }
  restorationRequired = false; phase = .restored; return true
 }
}
