import Foundation
@main struct ReceiverManagementTests {
 static func main() {
  precondition(ReceiverManagementCommand.openPairing.packet == [0x10,0xff,0x80,0xb2,1,0,60])
  precondition(ReceiverManagementCommand.closePairing.packet == [0x10,0xff,0x80,0xb2,2,0,0])
  for slot in UInt8(0)...7 {
   let command = ReceiverManagementCommand.unpair(slot:slot)
   if (1...6).contains(slot) { precondition(command.packet == [0x10,0xff,0x80,0xb2,3,slot,0]) }
   else { precondition(command.packet == nil) }
  }
  let command = ReceiverManagementCommand.openPairing
  precondition(command.parseReply([0x10,0xff,0x80,0xb2,0,0,0]) == .accepted)
  precondition(command.parseReply([0x10,0xff,0x7f,0x80,0xb2,7,0]) == .rejected(7))
  for malformed: [UInt8] in [[0x10,1,0x80,0xb2,0,0,0],[0x11,0xff,0x80,0xb2,0,0,0],[0x10,0xff,0x80,0xb3,0,0,0],[0x10,0xff,0x7f,0x81,0xb2,7,0],[]] {
   precondition(command.parseReply(malformed) == nil)
  }
  precondition(ReceiverManagementCommand.unpair(slot:0).parseReply([0x10,0xff,0x80,0xb2,0,0,0]) == nil)
  precondition(ReceiverPairingNotification.parse([0x10,0xff,0x4a,1,0,0,0]) == ReceiverPairingNotification(open:true,error:0))
  precondition(ReceiverPairingNotification.parse([0x10,0xff,0x4a,0,3,0,0]) == ReceiverPairingNotification(open:false,error:3))
  precondition(ReceiverPairingNotification.parse([0x10,0xff,0x4a,2,0,0,0]) == nil)
  precondition(ReceiverPairingNotification.parse([0x10,1,0x4a,0,1,0,0]) == nil)
  print("Receiver management framing tests passed")
 }
}
