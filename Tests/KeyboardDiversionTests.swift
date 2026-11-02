import Foundation
@main struct Checks {
 static func main() {
  let lease=KeyboardDiversionLease(endpoint:"receiver",slot:3,wirelessID:0x4076,featureIndex:6,cid:0xe9,capabilityFlags:0x20)
  let base=KeyboardReportingSnapshot(cid:0xe9,flags:0,mappedCID:0)
  let on=KeyboardReportingSnapshot(cid:0xe9,flags:1,mappedCID:0)
  var notification = [UInt8](repeating:0,count:20)
  notification[0]=0x11;notification[1]=3;notification[2]=6;notification[4]=0;notification[5]=0xe9
  precondition(KeyboardDivertedButtons.decode(notification,slot:3,featureIndex:6) == Set([UInt16(0xe9)]))
  precondition(KeyboardDivertedButtons.decode(notification,slot:1,featureIndex:6) == nil)
  notification[3]=0x21
  precondition(KeyboardDivertedButtons.decode(notification,slot:3,featureIndex:6) == nil)
  notification[3]=0;notification[5]=0
  precondition(KeyboardDivertedButtons.decode(notification,slot:3,featureIndex:6)?.isEmpty == true)
  for flags:UInt16 in [1,4,5] { var p=KeyboardDiversionPlanner(lease:lease); precondition(!p.acceptBaseline(.init(cid:0xe9,flags:flags,mappedCID:0))) }
  precondition(KeyboardReportingSnapshot.parse([0,1,0,0,0],expectedCID:0xe9) == nil)
  precondition(KeyboardReportingSnapshot.parse([0,0xe9,0,0],expectedCID:0xe9) == nil)
  precondition(KeyboardReportingSnapshot.parse([0,0xe9,0,0,0,1],expectedCID:0xe9)?.flags == 256)
  var p=KeyboardDiversionPlanner(lease:lease)
  precondition(p.prepareEnable(softwareID:7) == nil)
  precondition(p.acceptBaseline(base))
  let packet=p.prepareEnable(softwareID:7)!
  precondition(packet.count == 20 && Array(packet.prefix(9)) == [0x11,3,6,0x37,0,0xe9,3,0,0])
  p.acknowledgeWrite(); precondition(p.phase == .enableUncertain)
  p.writeTimedOut(); precondition(p.restorationRequired)
  precondition(p.observeEnabled(on) && p.phase == .active)
  let restore=p.prepareRestore(current:on,softwareID:7)!
  precondition(restore[6] == 2 && p.restorationRequired)
  p.acknowledgeWrite();p.writeTimedOut();precondition(p.restorationRequired)
  precondition(p.observeRestored(base) && !p.restorationRequired)
  var conflict=KeyboardDiversionPlanner(lease:lease);precondition(conflict.acceptBaseline(base));_ = conflict.prepareEnable(softwareID:7)
  precondition(conflict.prepareRestore(current:.init(cid:0xe9,flags:1,mappedCID:42),softwareID:7) == nil)
  precondition(conflict.phase == .conflict && conflict.restorationRequired)
  var uncertain=KeyboardDiversionPlanner(lease:lease);precondition(uncertain.acceptBaseline(base));_ = uncertain.prepareEnable(softwareID:7);uncertain.writeTimedOut()
  precondition(uncertain.prepareRestore(current:base,softwareID:7) == nil && uncertain.phase == .restored)
  print("PASS: diversion ownership, eligibility, uncertain writes, readback activation and conditional restoration")
 }
}
