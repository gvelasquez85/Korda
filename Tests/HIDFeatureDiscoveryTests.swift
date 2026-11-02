import Foundation
@main struct Checks {
 static func main() {
  let root = KeyboardFeatureQuery(slot:3,featureIndex:0,function:0,softwareID:7,parameters:[0x1b,0x04])
  precondition(root.packet == [0x10,3,0,7,0x1b,4,0])
  precondition(root.parse([0x10,3,0,7,0,0,0]) == .payload([0,0,0]))
  precondition(root.parse([0x10,3,0x8f,0,7,9,0]) == .error(9))
  precondition(root.permitsLegacyFallback(error:9) && !root.permitsLegacyFallback(error:2))
  precondition(!KeyboardFeatureQuery(slot:3,featureIndex:0,function:0,softwareID:7,parameters:[0x1b,0]).permitsLegacyFallback(error:9))
  precondition(root.parse([0x10,2,0,7,6,0,0]) == nil)
  precondition(root.parse([0x10,3,0,8,6,0,0]) == nil)
  precondition(root.parse([0x10,3,0x8f,0,8,9,0]) == nil)
  precondition(root.parse([0x10,3,0,7,0,0]) == nil)
  precondition(KeyboardFeatureQuery(slot:0,featureIndex:0,function:0,softwareID:7,parameters:[0x1b,4]).packet == nil)
  precondition(KeyboardFeatureQuery(slot:3,featureIndex:6,function:3,softwareID:7,parameters:[0,1,3]).packet == nil)
  precondition(KeyboardFeatureQuery(slot:3,featureIndex:6,function:2,softwareID:7,parameters:[0,1]).packet == nil, "Only count/info getters are needed in this probe")
  for function in UInt8(2)...15 {
   precondition(KeyboardFeatureQuery(slot:3,featureIndex:6,function:function,softwareID:7,parameters:[]).packet == nil)
  }
  precondition(KeyboardFeatureQuery(slot:3,featureIndex:0,function:0,softwareID:0,parameters:[0x1b,4]).packet == nil)
  precondition(KeyboardFeatureQuery(slot:3,featureIndex:0,function:0,softwareID:7,parameters:[0x22,5]).packet == nil)
  let q = KeyboardFeatureQuery(slot:3,featureIndex:6,function:1,softwareID:7,parameters:[2])
  var long = [UInt8](repeating:0,count:20);long[0]=0x11;long[1]=3;long[2]=6;long[3]=0x17
  precondition(q.parse(long) == .payload(Array(repeating:0,count:16)))
  let info = KeyboardControlInfo.parseV4([0,0xe9,0,1,0x20,0,0,0,1])!
  precondition(info.cid == 233 && info.task == 1 && info.flags == 0x120 && info.isDivertable)
  precondition(info.consumerUsage == 233)
  let catalog = KeyboardFeatureCatalog(endpoint:"test",slot:3,wirelessID:0x4076,featureID:0x1b04,featureIndex:6,controls:[info])
  precondition(catalog.control(forUsage:233)?.cid == 233)
  let ambiguous = KeyboardFeatureCatalog(endpoint:"test",slot:3,wirelessID:0x4076,featureID:0x1b04,featureIndex:6,controls:[info,info])
  precondition(ambiguous.control(forUsage:233) == nil)
  let legacy = KeyboardFeatureCatalog(endpoint:"test",slot:3,wirelessID:0x4076,featureID:0x1b00,featureIndex:6,controls:[info])
  precondition(legacy.control(forUsage:233) == nil)
  precondition(KeyboardControlInfo.parseV4([0,1,0,2,0,0,0,0]) == nil)
  precondition(KeyboardControlInfo.parseV1([0,1,0,2,0x10])?.isDivertable == false)
  print("PASS: bounded HID++ getters, response correlation, errors and control capability flags")
 }
}
