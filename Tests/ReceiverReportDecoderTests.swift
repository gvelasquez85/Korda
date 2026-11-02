@main struct ReceiverDecoderChecks {
 static func main() {
  func packet(slot: UInt8 = 1, type: UInt8 = 2, mask: UInt16 = 0, tail: [UInt8] = Array(repeating: 0, count: 10)) -> [UInt8] {
   [0x20, slot, type, UInt8(mask & 255), UInt8(mask >> 8)] + tail
  }
  let middle = ReceiverReportDecoder.decodeDJMouse(reportID: 0x20, data: packet(mask: 4), format: .reportIDPrefixed, previousMasks: [:])!
  precondition(middle.slot == 1 && middle.changes == [MouseButtonChange(button: 3, isDown: true)])
  let back = ReceiverReportDecoder.decodeDJMouse(reportID: 0x20, data: packet(slot: 2, mask: 8), format: .reportIDPrefixed, previousMasks: [1:4])!
  precondition(back.slot == 2 && back.changes == [MouseButtonChange(button: 4, isDown: true)])
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID: 0x20, data: packet(mask: 0), format: .reportIDPrefixed, previousMasks: [1:4])!.changes == [MouseButtonChange(button: 3, isDown: false)])
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID: 0x20, data: Array(packet(mask:16).dropFirst()), format: .payloadOnly, previousMasks: [:])!.changes == [MouseButtonChange(button:5,isDown:true)])
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID: 0x20, data: packet(mask: 3), format: .reportIDPrefixed, previousMasks: [:])!.changes.isEmpty)
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID: 0x20, data: packet(mask:4,tail:Array(repeating:255,count:10)), format:.reportIDPrefixed,previousMasks:[1:4])!.changes.isEmpty)
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID: 0x20,data:packet(type:1,mask:4),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID: 0x20,data:packet(type:3,mask:4),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  for slot: UInt8 in [0,7,255] { precondition(ReceiverReportDecoder.decodeDJMouse(reportID:0x20,data:packet(slot:slot,mask:4),format:.reportIDPrefixed,previousMasks:[:]) == nil) }
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID:2,data:packet(mask:4),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID:0x20,data:[0x20,1,2,4,0],format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID:0x20,data:packet(mask:4)+[0],format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeDJMouse(reportID:0x20,data:[0x21]+Array(packet(mask:4).dropFirst()),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  func feature(slot: UInt8 = 1, index: UInt8 = 6, function: UInt8 = 0, cids: [UInt16] = [], tail: UInt8 = 0) -> [UInt8] {
   let padded = cids + Array(repeating: UInt16(0), count: 4 - cids.count)
   return [0x11,slot,index,function] + padded.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] } + Array(repeating: tail, count: 8)
  }
  let diverted = ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:feature(cids:[0x52,0x53]),format:.reportIDPrefixed,previousMasks:[:])!
  precondition(diverted.slot == 1 && diverted.changes == [MouseButtonChange(button:3,isDown:true),MouseButtonChange(button:4,isDown:true)])
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:feature(cids:[0x56]),format:.reportIDPrefixed,previousMasks:[1:12])!.changes == [MouseButtonChange(button:3,isDown:false),MouseButtonChange(button:4,isDown:false),MouseButtonChange(button:5,isDown:true)])
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:feature(),format:.reportIDPrefixed,previousMasks:[1:4])!.changes == [MouseButtonChange(button:3,isDown:false)])
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:Array(feature(cids:[0x50,0x51,0x52]).dropFirst()),format:.payloadOnly,previousMasks:[:])!.changes == [MouseButtonChange(button:3,isDown:true)])
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:feature(slot:2,cids:[0x53]),format:.reportIDPrefixed,previousMasks:[1:4])!.changes == [MouseButtonChange(button:4,isDown:true)])
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:feature(cids:[0x99]),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:feature(tail:1),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:feature(index:5),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:feature(function:1),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:feature(slot:7),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x10,data:feature(),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  precondition(ReceiverReportDecoder.decodeSynthetic1B04(reportID:0x11,data:Array(feature().dropLast()),format:.reportIDPrefixed,previousMasks:[:]) == nil)
  var paired: [UInt8] = [0x20,2,0x41,0,0x28,0x10] + Array(repeating:0,count:9)
  precondition(ReceiverReportDecoder.decodeM570Identity(reportID:0x20,data:paired,format:.reportIDPrefixed)?.slot == 2)
  paired[3] = 2
  precondition(ReceiverReportDecoder.decodeM570Identity(reportID:0x20,data:paired,format:.reportIDPrefixed) == nil)
  paired[3] = 0; paired[4] = 0x29
  precondition(ReceiverReportDecoder.decodeM570Identity(reportID:0x20,data:paired,format:.reportIDPrefixed) == nil)
  paired[4] = 0x28; paired[2] = 1
  precondition(ReceiverReportDecoder.decodeM570Identity(reportID:0x20,data:paired,format:.reportIDPrefixed) == nil)
  paired[2] = 0x41; paired[0] = 0x21
  let pairedLong = paired + Array(repeating:UInt8(0),count:17)
  precondition(ReceiverReportDecoder.decodeM570Identity(reportID:0x21,data:pairedLong,format:.reportIDPrefixed)?.slot == 2)
  precondition(ReceiverReportDecoder.decodeM570Identity(reportID:0x21,data:paired,format:.reportIDPrefixed) == nil)
  print("PASS: synthetic candidate1B04 strict framing, CID states, tail, feature, slot and unknown rejection")
  print("PASS: DJ mouse-only parser, slot isolation, framing, extra-button transitions and movement/keyboard exclusion")
 }
}
