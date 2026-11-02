@main struct MouseReportDecoderChecks {
 static func main() {
  func payload(_ mask: UInt16, movement: [UInt8] = [0, 0, 0, 0, 0]) -> [UInt8] {
   [UInt8(mask & 255), UInt8(mask >> 8)] + movement
  }
  let middle = MouseReportDecoder.decode(reportID: 2, data: payload(4), format: .payloadOnly, previousExtraButtonsMask: 0)!
  precondition(middle.changes == [MouseButtonChange(button: 3, isDown: true)])
  let back = MouseReportDecoder.decode(reportID: 2, data: [2] + payload(8), format: .reportIDPrefixed, previousExtraButtonsMask: 0)!
  precondition(back.changes == [MouseButtonChange(button: 4, isDown: true)])
  let forward = MouseReportDecoder.decode(reportID: 2, data: payload(16), format: .payloadOnly, previousExtraButtonsMask: 0)!
  precondition(forward.changes == [MouseButtonChange(button: 5, isDown: true)])
  let released = MouseReportDecoder.decode(reportID: 2, data: payload(0), format: .payloadOnly, previousExtraButtonsMask: 4)!
  precondition(released.changes == [MouseButtonChange(button: 3, isDown: false)])
  precondition(MouseReportDecoder.decode(reportID: 2, data: payload(3), format: .payloadOnly, previousExtraButtonsMask: 0)!.changes.isEmpty)
  precondition(MouseReportDecoder.decode(reportID: 2, data: payload(4, movement: [255, 127, 255, 1, 255]), format: .payloadOnly, previousExtraButtonsMask: 4)!.changes.isEmpty)
  precondition(MouseReportDecoder.decode(reportID: 2, data: payload(0, movement: [255, 127, 255, 1, 255]), format: .payloadOnly, previousExtraButtonsMask: 0)!.changes.isEmpty)
  precondition(MouseReportDecoder.decode(reportID: 3, data: payload(4), format: .payloadOnly, previousExtraButtonsMask: 0) == nil)
  precondition(MouseReportDecoder.decode(reportID: 2, data: [3] + payload(4), format: .reportIDPrefixed, previousExtraButtonsMask: 0) == nil)
  precondition(MouseReportDecoder.decode(reportID: 2, data: [2, 4], format: .reportIDPrefixed, previousExtraButtonsMask: 0) == nil)
  precondition(MouseReportDecoder.decode(reportID: 2, data: [4, 0], format: .payloadOnly, previousExtraButtonsMask: 0) == nil)
  precondition(MouseReportDecoder.decode(reportID: 2, data: payload(4) + [0], format: .payloadOnly, previousExtraButtonsMask: 0) == nil)
  let last = MouseReportDecoder.decode(reportID: 2, data: payload(0x8000), format: .payloadOnly, previousExtraButtonsMask: 0)!
  precondition(last.extraButtonsMask == 0x8000 && last.changes == [MouseButtonChange(button: 16, isDown: true)])
  precondition(MouseReportDecoder.decode(reportID: 2, data: payload(4), format: .payloadOnly, previousExtraButtonsMask: 4)!.changes.isEmpty)
  print("PASS: mouse report2 extra-button transitions, normalization, lengths, keyboard exclusion, and movement privacy")
 }
}
