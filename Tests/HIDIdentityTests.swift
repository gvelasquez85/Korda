import Foundation
@main struct IdentityChecks {
 static func main() {
  precondition(HIDIdentityQuery(slot:1,kind:.pairing).request == [0x10,0xff,0x83,0xb5,0x20,0,0])
  precondition(HIDIdentityQuery(slot:6,kind:.name).request == [0x10,0xff,0x83,0xb5,0x45,0,0])
  var pairing = [UInt8](repeating:0,count:20); pairing[0]=0x11;pairing[1]=0xff;pairing[2]=0x83;pairing[3]=0xb5;pairing[4]=0x20;pairing[7]=0x10;pairing[8]=0x28;pairing[11]=8
  let q = HIDIdentityQuery(slot:1,kind:.pairing)
  precondition(q.parse(pairing)?.wirelessID == 0x1028)
  precondition(q.parse(Array(pairing.dropLast())) == nil)
  pairing[4]=0x21;precondition(q.parse(pairing) == nil);pairing[4]=0x20
  pairing[1]=1;precondition(q.parse(pairing) == nil);pairing[1]=0xff
  pairing[2]=0x82;precondition(q.parse(pairing) == nil);pairing[2]=0x83
  pairing[7]=0;pairing[8]=0;precondition(q.parse(pairing) == nil)
  var name = [UInt8](repeating:0,count:20);name[0]=0x11;name[1]=0xff;name[2]=0x83;name[3]=0xb5;name[4]=0x40;name[5]=4
  name.replaceSubrange(6..<10,with:Array("M570".utf8))
  precondition(HIDIdentityQuery(slot:1,kind:.name).parse(name)?.name == "M570")
  name[5]=15;precondition(HIDIdentityQuery(slot:1,kind:.name).parse(name) == nil)
  precondition(!HIDIdentityQuery(slot:0,kind:.pairing).isValid)
  precondition(!HIDIdentityQuery(slot:7,kind:.pairing).isValid)
  let keyboard = HIDDeviceIdentity(endpoint:"test",slot:4,wirelessID:0x4024,kind:1,name:"K400",checkedAt:Date())
  precondition(keyboard.displayName == "K400r" && keyboard.categoryName == "Teclado")
  let unknown = HIDDeviceIdentity(endpoint:"test",slot:2,wirelessID:0x4055,kind:2,name:nil,checkedAt:Date())
  precondition(unknown.displayName == "Ratón sin identificar")
  print("PASS: identity read-only packets, exact response correlation, lengths, names and empty slots")
 }
}
