import Foundation
@main struct DigitalAudioChecks {
 static func main() {
  precondition(DigitalAudioController.clampedLevel(-1)==0)
  precondition(DigitalAudioController.clampedLevel(2)==1)
  precondition(DigitalAudioController.clampedLevel(.nan)==0)
  precondition(DigitalAudioController.clampedLevel(0.25)==0.25)
  let outputs=AudioOutputInfo.inventory()
  precondition(outputs.allSatisfy{!$0.id.isEmpty && !$0.name.isEmpty})
  precondition(Set(outputs.map(\.id)).count==outputs.count)
  print("Digital audio level and read-only inventory checks passed (\(outputs.count) outputs). No capture started.")
 }
}
