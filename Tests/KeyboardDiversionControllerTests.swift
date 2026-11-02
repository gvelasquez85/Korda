import Foundation
@main struct Checks {
 static func main() {
  var packets:[[UInt8]]=[]
  let c=KeyboardDiversionController(send:{packets.append($0);return true},emit:{_ in})
  c.validateIdentity={_ in true}
  let lease=KeyboardDiversionLease(endpoint:"receiver",slot:3,wirelessID:0x4076,featureIndex:6,cid:0xe9,capabilityFlags:0x20)
  func reply(_ payload:[UInt8]) { let sent=packets.last!;var bytes=[UInt8](repeating:0,count:20);bytes.replaceSubrange(0..<4,with:[0x11,sent[1],sent[2],sent[3]]);bytes.replaceSubrange(4..<(4+payload.count),with:payload);precondition(c.receive(bytes)) }
  var activated=false
  c.activate(source:"test",lease:lease){ok,_ in activated=ok}
  precondition(packets.count == 1 && packets[0][3] >> 4 == 2)
  reply([0,0xe9,0,0,0,0]);precondition(packets.last![6] == 3)
  reply([]);precondition(!activated && c.hasRestorationObligations)
  reply([0,0xe9,1,0,0,0]);precondition(activated && c.isActive(source:"test"))
  var restored=false
  c.restore(source:"test"){ok,_ in restored=ok}
  reply([0,0xe9,1,0,0,0]);precondition(packets.last![6] == 2)
  reply([]);precondition(!restored && c.hasRestorationObligations)
  reply([0,0xe9,0,0,0,0]);precondition(restored && !c.hasRestorationObligations)
  precondition(!c.receive([0x10,3,6,0x27,0,0,0]))
  var rejected=false;c.validateIdentity={_ in false};c.activate(source:"other",lease:lease){ok,_ in rejected = !ok};precondition(rejected)
  print("PASS: controller serialized getter/setter/readback, restore confirmation and identity rejection")
 }
}
