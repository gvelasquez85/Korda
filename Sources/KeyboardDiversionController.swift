import Foundation

// Main-run-loop transport coordinator. The owner must retain the receiver until
// all restoration obligations resolve. No IOKit or actual transport is used here.
final class KeyboardDiversionController {
 typealias Completion = (Bool,String) -> Void
 var validateIdentity: (KeyboardDiversionLease)->Bool = { _ in false }
 var stateChanged: (() -> Void)?
 private let send: ([UInt8])->Bool
 private let emit: (String)->Void
 private var planners: [String:KeyboardDiversionPlanner] = [:]
 private var pending: (lease:KeyboardDiversionLease,function:UInt8,swid:UInt8,completion:(KeyboardFeatureReply?)->Void)?
 private var timer: Timer?
 private var swid:UInt8 = 0
 private(set) var busy = false
 private var restoring = false
 private var queuedRestores:[Completion] = []
 var hasRestorationObligations:Bool { planners.values.contains{$0.restorationRequired} }
 init(send:@escaping([UInt8])->Bool,emit:@escaping(String)->Void) { self.send=send;self.emit=emit }
 func isActive(source:String)->Bool { planners[source]?.phase == .active }
 func requiresRestoration(source:String)->Bool { planners[source]?.restorationRequired == true }
 func activeSources()->[String:KeyboardDiversionLease] { planners.filter{$0.value.phase == .active}.mapValues{$0.lease} }
 private func request(_ lease:KeyboardDiversionLease,function:UInt8,packet:(UInt8)->[UInt8]?,completion:@escaping(KeyboardFeatureReply?)->Void) {
  guard pending == nil,validateIdentity(lease) else { completion(nil);return }
  swid = swid == 15 ? 1 : swid+1
  guard let bytes=packet(swid) else { completion(nil);return }
  pending=(lease,function,swid,completion)
  timer=Timer.scheduledTimer(withTimeInterval:2,repeats:false){[weak self] _ in self?.finishRequest(nil)}
  if !send(bytes) { finishRequest(nil) }
 }
 private func finishRequest(_ reply:KeyboardFeatureReply?) {
  guard let operation=pending else{return};pending=nil;timer?.invalidate();timer=nil
  operation.completion(reply)
 }
 func receive(_ bytes:[UInt8])->Bool {
  guard let p=pending, ((bytes.count == 7 && bytes[0] == 0x10)||(bytes.count == 20 && bytes[0] == 0x11)),bytes[1] == p.lease.slot else{return false}
  let address=(p.function << 4)|p.swid
  if bytes[2] == 0x8f {
   guard bytes[3] == p.lease.featureIndex,bytes[4] == address else{return false}
   finishRequest(.error(bytes[5]));return true
  }
  guard bytes[2] == p.lease.featureIndex,bytes[3] == address else{return false}
  finishRequest(.payload(Array(bytes.dropFirst(4))));return true
 }
 private func read(_ lease:KeyboardDiversionLease,completion:@escaping(KeyboardReportingSnapshot?)->Void) {
  request(lease,function:2,packet:{ id in [0x10,lease.slot,lease.featureIndex,0x20|id,UInt8(lease.cid >> 8),UInt8(lease.cid & 255),0] }) { reply in
   if case .payload(let bytes)?=reply { completion(KeyboardReportingSnapshot.parse(bytes,expectedCID:lease.cid)) } else { completion(nil) }
  }
 }
 func activate(source:String,lease:KeyboardDiversionLease,completion:@escaping Completion) {
  guard !busy,!restoring,queuedRestores.isEmpty,!planners.values.contains(where:{$0.restorationRequired && $0.phase != .active}),planners[source] == nil,lease.isEligible else{completion(false,"Hay una operación o restauración pendiente.");return}
  busy=true;stateChanged?()
  read(lease){[weak self] baseline in
   guard let self else{return}
   var planner=KeyboardDiversionPlanner(lease:lease)
   guard let baseline,planner.acceptBaseline(baseline) else{self.end(false,"No se obtuvo una base exclusiva válida.",completion);return}
   self.planners[source]=planner
   self.request(lease,function:3,packet:{ id in
    guard var current=self.planners[source] else{return nil};let packet=current.prepareEnable(softwareID:id);self.planners[source]=current;return packet
   }) { reply in
    // Even an error is followed by readback: dispatch may have changed firmware.
    self.read(lease){ snapshot in
     if case .payload?=reply,let snapshot,var current=self.planners[source],current.observeEnabled(snapshot) {
      self.planners[source]=current;self.end(true,"Desvío confirmado mediante lectura.",completion)
     } else {
      self.restoreOne(source){ restored,_ in self.end(false,restored ? "Activación no confirmada; estado original recuperado." : "Activación incierta; restauración pendiente.",completion) }
     }
    }
   }
  }
 }
 private func end(_ ok:Bool,_ message:String,_ completion:Completion) {
  busy=false;stateChanged?();emit(message);completion(ok,message)
  if !queuedRestores.isEmpty {
   let waiting=queuedRestores;queuedRestores=[]
   restoreAll { success,status in waiting.forEach{$0(success,status)} }
  }
 }
 private func restoreOne(_ source:String,completion:@escaping Completion) {
  guard let planner=planners[source],planner.restorationRequired else{planners.removeValue(forKey:source);completion(true,"Sin obligación.");return}
  let lease=planner.lease
  read(lease){[weak self] snapshot in
   guard let self else{return}
   guard let snapshot,var current=self.planners[source] else{completion(false,"No se pudo leer para restaurar.");return}
   // Reserve this SWID for the subsequent setter; request increments identically.
   let next:UInt8=self.swid == 15 ? 1 : self.swid+1
   let bytes=current.prepareRestore(current:snapshot,softwareID:next)
   self.planners[source]=current
   if !current.restorationRequired { self.planners.removeValue(forKey:source);completion(true,"Restauración observada.");return }
   guard let bytes else{completion(false,"Conflicto o estado no verificable; no se sobrescribió.");return}
   self.request(lease,function:3,packet:{_ in bytes}){ _ in
    self.read(lease){ result in
     guard let result,var latest=self.planners[source],latest.observeRestored(result) else{completion(false,"Restauración sin confirmar.");return}
     self.planners.removeValue(forKey:source);completion(true,"Restauración confirmada.")
    }
   }
  }
 }
 func restore(source:String,completion:@escaping Completion) {
  guard !busy,!restoring else { completion(false,"Hay una operación en curso; la restauración individual sigue pendiente.");return }
  restoring=true;busy=true;stateChanged?()
  restoreOne(source){[weak self] ok,message in
   guard let self else{return};self.restoring=false;self.end(ok,message,completion)
  }
 }
 func restoreAll(completion:@escaping Completion) {
  guard !busy,!restoring else{queuedRestores.append(completion);return}
  restoring=true;busy=true;stateChanged?()
  restoreQueue(Array(planners.keys),success:true){[weak self] ok in
   guard let self else{return};self.restoring=false;self.end(ok,ok ? "Restauraciones verificadas." : "Quedan restauraciones pendientes.",completion)
  }
 }
 private func restoreQueue(_ sources:[String],success:Bool,completion:@escaping(Bool)->Void) {
  guard let first=sources.first else{completion(success);return}
  restoreOne(first){[weak self] ok,_ in self?.restoreQueue(Array(sources.dropFirst()),success:success && ok,completion:completion) }
 }
 deinit { timer?.invalidate() }
}
