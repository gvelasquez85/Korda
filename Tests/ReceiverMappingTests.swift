import Foundation
@main struct ReceiverMappingChecks {
 static func main() throws {
  let a = ReceiverMappingProfile(endpoint:"1133:50475:123456:65280:1",slot:1,route:.synthetic1B04)
  let otherReceiver = ReceiverMappingProfile(endpoint:"1133:50475:999:65280:1",slot:1,route:.synthetic1B04)
  let otherSlot = ReceiverMappingProfile(endpoint:a.endpoint,slot:2,route:.synthetic1B04)
  let otherRoute = ReceiverMappingProfile(endpoint:a.endpoint,slot:1,route:.djMouse)
  precondition(Set([a.id,otherReceiver.id,otherSlot.id,otherRoute.id]).count == 4)
  precondition(!a.enrolled)
  var runtime = ReceiverMappingRuntime()
  precondition(!runtime.executionEnabled && !runtime.listening)
  let enrolled:Set<String> = [a.id]
  precondition(!runtime.consume(profile:a,button:4,isDown:true,enrolled:enrolled).execute)
  _ = runtime.consume(profile:a,button:4,isDown:false,enrolled:enrolled)
  runtime.listening = true; runtime.executionEnabled = true
  precondition(!runtime.consume(profile:otherSlot,button:4,isDown:true,enrolled:enrolled).execute)
  precondition(!runtime.consume(profile:otherReceiver,button:4,isDown:true,enrolled:enrolled).learn)
  precondition(!runtime.consume(profile:otherRoute,button:4,isDown:true,enrolled:enrolled).execute)
  let first = runtime.consume(profile:a,button:4,isDown:true,enrolled:enrolled)
  precondition(first.execute && first.learn && first.source == a.source(button:4))
  precondition(!runtime.consume(profile:a,button:4,isDown:true,enrolled:enrolled).execute)
  precondition(!runtime.consume(profile:a,button:4,isDown:false,enrolled:enrolled).execute)
  precondition(runtime.consume(profile:a,button:4,isDown:true,enrolled:enrolled).execute)
  runtime.reset(); runtime.executionEnabled = false
  let learn = runtime.consume(profile:a,button:5,isDown:true,enrolled:enrolled)
  precondition(learn.learn && !learn.execute)
  _ = runtime.consume(profile:a,button:5,isDown:false,enrolled:enrolled)
  precondition(!runtime.consume(profile:a,button:5,isDown:true,enrolled:[]).learn)
  var configured = a; configured.enrolled = true
  precondition(!configured.permitsIdentifiedDevice(0x1028))
  configured.verifiedWirelessID = 0x1028
  precondition(configured.permitsIdentifiedDevice(0x1028))
  precondition(!configured.permitsIdentifiedDevice(0x4077))
  precondition(!configured.permitsIdentifiedDevice(nil))
  let data = try JSONEncoder().encode([configured])
  let restored = try JSONDecoder().decode([ReceiverMappingProfile].self,from:data)
  precondition(restored == [configured])
  let restarted = ReceiverMappingRuntime()
  precondition(!restarted.executionEnabled && !restarted.listening)
  precondition(!String(decoding:data,as:UTF8.self).contains("executionEnabled"))
  precondition(!runtime.consume(profile:a,button:1,isDown:true,enrolled:enrolled).learn)
  precondition(a.buttonLabel(4) == "Botón 4")
  var named = a; named.enrolled = true; named.buttonLabelsConfirmed = true
  precondition(named.buttonLabel(4) == "Atrás (botón 4, según prueba)")
  named.enrolled = false
  precondition(named.buttonLabel(4) == "Botón 4")
  precondition(otherSlot.buttonLabel(4) == "Botón 4")
  precondition(CapturePolicy.allows(page:12,usage:233) && !CapturePolicy.allows(page:7,usage:4))
  print("PASS: receiver enrollment, endpoint/slot/route isolation, press edges, persistence without autoexecution, standard capture unchanged")
 }
}
