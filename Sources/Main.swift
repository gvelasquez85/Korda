import SwiftUI
import AppKit
import IOKit.hid
import AVFoundation
import ApplicationServices
import ServiceManagement
import Combine
import UniformTypeIdentifiers


// Descriptor identities observed in evidence/hid-current.plist. These are static
// layout declarations, never captured input bytes. Unknown layouts are rejected.
private enum KnownMouseReportLayout {
 static let descriptors: Set<Data> = [
  Data([5, 1, 9, 2, 161, 1, 133, 2, 9, 1, 161, 0, 5, 9, 25, 1, 41, 16, 21, 0, 37, 1, 149, 16, 117, 1, 129, 2, 5, 1, 22, 1, 248, 38, 255, 7, 117, 12, 149, 2, 9, 48, 9, 49, 129, 6, 21, 129, 37, 127, 117, 8, 149, 1, 9, 56, 129, 6, 5, 12, 10, 56, 2, 149, 1, 129, 6, 192, 192, 5, 12, 9, 1, 161, 1, 133, 3, 117, 16, 149, 2, 21, 1, 38, 255, 2, 25, 1, 42, 255, 2, 129, 0, 192, 5, 1, 9, 128, 161, 1, 133, 4, 117, 2, 149, 1, 21, 1, 37, 3, 9, 130, 9, 129, 9, 131, 129, 96, 117, 6, 129, 3, 192, 6, 188, 255, 9, 136, 161, 1, 133, 8, 25, 1, 41, 255, 21, 1, 38, 255, 0, 117, 8, 149, 1, 129, 0, 192]),
  Data([5, 1, 9, 2, 161, 1, 133, 2, 9, 1, 161, 0, 5, 9, 25, 1, 41, 16, 21, 0, 37, 1, 149, 16, 117, 1, 129, 2, 5, 1, 22, 1, 248, 38, 255, 7, 117, 12, 149, 2, 9, 48, 9, 49, 129, 6, 21, 129, 37, 127, 117, 8, 149, 1, 9, 56, 129, 6, 5, 12, 10, 56, 2, 149, 1, 129, 6, 192, 192]),
  Data([5, 1, 9, 2, 161, 1, 133, 2, 9, 1, 161, 0, 149, 16, 117, 1, 21, 0, 37, 1, 5, 9, 25, 1, 41, 16, 129, 2, 149, 2, 117, 12, 22, 1, 248, 38, 255, 7, 5, 1, 9, 48, 9, 49, 129, 6, 149, 1, 117, 8, 21, 129, 37, 127, 9, 56, 129, 6, 149, 1, 5, 12, 10, 56, 2, 129, 6, 192, 192, 5, 12, 9, 1, 161, 1, 133, 3, 149, 2, 117, 16, 21, 1, 38, 255, 2, 25, 1, 42, 255, 2, 129, 0, 192, 5, 1, 9, 128, 161, 1, 133, 4, 149, 1, 117, 2, 21, 1, 37, 3, 9, 130, 9, 129, 9, 131, 129, 0, 117, 6, 129, 3, 192, 6, 188, 255, 9, 136, 161, 1, 133, 8, 149, 1, 117, 8, 21, 1, 38, 255, 0, 25, 1, 41, 255, 129, 0, 192])
 ]
 static func accepts(_ device: IOHIDDevice) -> Bool {
  func number(_ key: String) -> Int? { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue }
  guard number(kIOHIDVendorIDKey) == 1133,
        [50475, 4096].contains(number(kIOHIDProductIDKey) ?? -1),
        number(kIOHIDPrimaryUsagePageKey) == 1, number(kIOHIDPrimaryUsageKey) == 2,
        let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data else { return false }
  return descriptors.contains(descriptor)
 }
}
private final class MouseReportRegistration {
 let device: IOHIDDevice
 let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 8)
 weak var store: DeviceStore?
 var previousMask: UInt16 = 0
 init(device: IOHIDDevice, store: DeviceStore) {
  self.device = device; self.store = store
  buffer.initialize(repeating: 0, count: 8)
  IOHIDDeviceRegisterInputReportCallback(device, buffer, 8, { context, result, _, type, reportID, bytes, count in
   guard let context else { return }
   let registration = Unmanaged<MouseReportRegistration>.fromOpaque(context).takeUnretainedValue()
   guard result == kIOReturnSuccess, type == kIOHIDReportTypeInput, reportID == 2 else { return }
   registration.receive(reportID: reportID, bytes: bytes, count: count)
  }, Unmanaged.passUnretained(self).toOpaque())
 }
 func receive(reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, count: CFIndex) {
  guard let store, store.rawDiagnosticsEnabled, store.capturing else { return }
  store.rawReportCount += 1
  guard count == 7 || count == 8 else { store.rawRejectedCount += 1; return }
  // IOHID callback layouts differ by driver: normalize explicitly by exact length.
  let format: MouseReportBufferFormat = count == 8 ? .reportIDPrefixed : .payloadOnly
  let ephemeral = Array(UnsafeBufferPointer(start: bytes, count: count))
  guard let result = MouseReportDecoder.decode(reportID: reportID, data: ephemeral, format: format, previousExtraButtonsMask: previousMask) else { store.rawRejectedCount += 1; return }
  previousMask = result.extraButtonsMask
  for change in result.changes { store.recordRawButton(change, device: device) }
 }
 deinit {
  // All callbacks and removal run on the same scheduled main run loop.
  // Unregister before freeing the report buffer/context.
  IOHIDDeviceRegisterInputReportCallback(device, buffer, 8, nil, nil)
  buffer.deinitialize(count: 8); buffer.deallocate()
 }
}


// Exact vendor collection descriptors observed locally. Never match on name alone.
private enum KnownReceiverReportLayout {
 static let descriptors: Set<Data> = [
  Data([6, 0, 255, 9, 1, 161, 1, 133, 16, 117, 8, 149, 6, 21, 0, 38, 255, 0, 9, 1, 129, 0, 9, 1, 145, 0, 192, 6, 0, 255, 9, 2, 161, 1, 133, 17, 117, 8, 149, 19, 21, 0, 38, 255, 0, 9, 2, 129, 0, 9, 2, 145, 0, 192, 6, 0, 255, 9, 4, 161, 1, 133, 32, 117, 8, 149, 14, 21, 0, 38, 255, 0, 9, 65, 129, 0, 9, 65, 145, 0, 133, 33, 149, 31, 21, 0, 38, 255, 0, 9, 66, 129, 0, 9, 66, 145, 0, 192]),
  Data([6, 0, 255, 9, 1, 161, 1, 133, 16, 149, 6, 117, 8, 21, 0, 38, 255, 0, 9, 1, 129, 0, 9, 1, 145, 0, 192, 6, 0, 255, 9, 2, 161, 1, 133, 17, 149, 19, 117, 8, 21, 0, 38, 255, 0, 9, 2, 129, 0, 9, 2, 145, 0, 192, 6, 0, 255, 9, 4, 161, 1, 133, 32, 149, 14, 117, 8, 21, 0, 38, 255, 0, 9, 65, 129, 0, 9, 65, 145, 0, 133, 33, 149, 31, 9, 66, 129, 0, 9, 66, 145, 0, 192])
 ]
 static func accepts(_ device: IOHIDDevice) -> Bool {
  func number(_ key: String) -> Int? { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue }
  guard number(kIOHIDVendorIDKey) == 1133, number(kIOHIDProductIDKey) == 50475,
        number(kIOHIDPrimaryUsagePageKey) == 65280, number(kIOHIDPrimaryUsageKey) == 1,
        number(kIOHIDMaxInputReportSizeKey) == 32,
        let descriptor = IOHIDDeviceGetProperty(device,kIOHIDReportDescriptorKey as CFString) as? Data else { return false }
  return descriptors.contains(descriptor)
 }
}
private final class ReceiverReportRegistration {
 let device: IOHIDDevice
 let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity:32)
 weak var store: DeviceStore?
 var identityQueue: [HIDIdentityQuery] = []
 var pendingIdentity: HIDIdentityQuery?
 var identityTimer: Timer?
 var pendingManagement: ReceiverManagementCommand?
 var managementTimer: Timer?
 var unpairVerification: (slot:UInt8,wpid:UInt16)?
 var discoveryTarget: HIDDeviceIdentity?
 var pendingFeature: KeyboardFeatureQuery?
 var featureTimer: Timer?
 var discoveryFeature: UInt16 = 0x1b04
 var discoveryIndex: UInt8 = 0
 var discoveryCount: UInt8 = 0
 var discoveryPosition: UInt8 = 0
 var discoverySoftwareID: UInt8 = 1
 var featureBusy: Bool { discoveryTarget != nil }
 var diversionController: KeyboardDiversionController?
 var identityBusy: Bool { pendingIdentity != nil || !identityQueue.isEmpty }
 var djMasks: [UInt8:UInt16] = [:]
 var featureMasks: [UInt8:UInt16] = [:]
 var keyboardHeld = Set<String>()
 init(device: IOHIDDevice, store: DeviceStore) {
  self.device = device; self.store = store
  diversionController = KeyboardDiversionController(send:{ [weak self] packet in
   guard let self else { return false }
   return packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(self.device,kIOHIDReportTypeOutput,CFIndex(packet[0]),$0.baseAddress!,packet.count) } == kIOReturnSuccess
  },emit:{ [weak store] message in store?.exclusiveStatus = message })
  diversionController?.validateIdentity = { [weak store] lease in store?.verifiedIdentities[lease.endpoint + "|slot=\(lease.slot)"]?.wirelessID == lease.wirelessID }
  diversionController?.stateChanged = { [weak store,weak self] in
   if let self,let controller = self.diversionController { self.keyboardHeld = self.keyboardHeld.filter{controller.isActive(source:$0)} }
   store?.objectWillChange.send()
  }
  buffer.initialize(repeating:0,count:32)
  IOHIDDeviceRegisterInputReportCallback(device,buffer,32,{ context,result,_,type,reportID,bytes,count in
   guard let context else { return }
   let registration = Unmanaged<ReceiverReportRegistration>.fromOpaque(context).takeUnretainedValue()
   guard let store = registration.store, store.receiverDiagnosticsEnabled, store.capturing else { return }
   guard result == kIOReturnSuccess, type == kIOHIDReportTypeInput else { store.receiverIgnoredCount += 1; return }
   registration.receive(reportID:reportID,bytes:bytes,count:count)
  },Unmanaged.passUnretained(self).toOpaque())
 }
 func identifyDevices() {
  guard pendingIdentity == nil, pendingManagement == nil, unpairVerification == nil, !featureBusy, diversionController?.busy != true else { return }
  identityQueue = (1...6).flatMap { slot in [HIDIdentityQuery(slot:UInt8(slot),kind:.pairing),HIDIdentityQuery(slot:UInt8(slot),kind:.name)] }
  nextIdentityQuery()
 }
 func verifyAndUnpair(slot:UInt8,wpid:UInt16) {
  guard !identityBusy, pendingManagement == nil, unpairVerification == nil, !featureBusy, (1...6).contains(slot) else { return }
  unpairVerification = (slot,wpid)
  identityQueue = [HIDIdentityQuery(slot:slot,kind:.pairing)]
  nextIdentityQuery()
 }
 func sendManagement(_ command:ReceiverManagementCommand) {
  guard !identityBusy, pendingManagement == nil, !featureBusy, let packet = command.packet, let store else { return }
  pendingManagement = command
  let result = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device,kIOHIDReportTypeOutput,0x10,$0.baseAddress!,packet.count) }
  guard result == kIOReturnSuccess else { pendingManagement = nil; store.managementFinished(endpoint:store.identity(device),command:command,accepted:false,message:"No se pudo enviar la orden (\(result)). No se reintenta automáticamente."); return }
  managementTimer = Timer.scheduledTimer(withTimeInterval:2,repeats:false) { [weak self] _ in
   guard let self, let store = self.store, let command = self.pendingManagement else { return }
   self.pendingManagement = nil
   store.managementFinished(endpoint:store.identity(self.device),command:command,accepted:false,message:"Sin respuesta a la orden. Su resultado es desconocido; consulta el inventario antes de repetirla.")
  }
 }
 func discoverKeyboard(_ target:HIDDeviceIdentity) {
  guard !identityBusy, pendingManagement == nil, !featureBusy, diversionController?.busy != true, let store else { return }
  discoveryTarget = target; discoveryFeature = 0x1b04; discoveryIndex = 0; discoveryPosition = 0
  store.keyboardCatalogs.removeValue(forKey:target.key)
  store.keyboardControls[target.key] = []; store.keyboardDiscoveryStatus[target.key] = "Consultando capacidades del teclado, sin modificar su configuración…"
  store.keyboardDiscoveryTrace[target.key] = []
  sendFeature(index:0,function:0,parameters:[0x1b,0x04])
 }
 private func sendFeature(index:UInt8,function:UInt8,parameters:[UInt8]) {
  guard let target = discoveryTarget, let store, store.verifiedIdentities[target.key]?.wirelessID == target.wirelessID, store.capturing else { finishDiscovery("Identidad o captura cambió. Consulta cancelada."); return }
  discoverySoftwareID = discoverySoftwareID == 15 ? 1 : discoverySoftwareID + 1
  let query = KeyboardFeatureQuery(slot:target.slot,featureIndex:index,function:function,softwareID:discoverySoftwareID,parameters:parameters)
  guard let packet = query.packet else { finishDiscovery("Consulta rechazada por la política de sólo lectura."); return }
  pendingFeature = query
  let context = String(format:"Función %04X · índice %d · consulta %d · SWID %d",discoveryFeature,index,function,discoverySoftwareID)
  store.keyboardDiscoveryTrace[target.key,default:[]].append("Enviada: " + context)
  let result = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device,kIOHIDReportTypeOutput,0x10,$0.baseAddress!,packet.count) }
  guard result == kIOReturnSuccess else { finishDiscovery("No se pudo enviar la consulta (\(result))."); return }
  featureTimer = Timer.scheduledTimer(withTimeInterval:1.2,repeats:false) { [weak self] _ in self?.finishDiscovery("Sin respuesta: \(context). No se cambió la configuración del teclado.") }
 }
 private func finishDiscovery(_ message:String) {
  featureTimer?.invalidate(); featureTimer = nil; pendingFeature = nil
  if let target = discoveryTarget {
   store?.keyboardDiscoveryStatus[target.key] = message
   store?.keyboardDiscoveryTrace[target.key,default:[]].append(message)
  }
  discoveryTarget = nil
  store?.identityWorkDidChange()
 }
 private func consumeFeature(_ reply:KeyboardFeatureReply,query:KeyboardFeatureQuery) {
  guard let target = discoveryTarget, let store, store.verifiedIdentities[target.key]?.wirelessID == target.wirelessID else { finishDiscovery("La identidad cambió. Consulta cancelada."); return }
  switch reply {
  case .error(let code):
   store.keyboardDiscoveryTrace[target.key,default:[]].append("Respuesta de error HID++ \(code), índice \(query.featureIndex), consulta \(query.function).")
   if query.permitsLegacyFallback(error:code), discoveryFeature == 0x1b04 {
    store.keyboardDiscoveryStatus[target.key] = "La consulta 1B04 fue rechazada; comprobando la función alternativa 1B00…"
    discoveryFeature = 0x1b00; sendFeature(index:0,function:0,parameters:[0x1b,0x00])
   } else {
    let stage = query.featureIndex == 0 ? "búsqueda de función" : (query.function == 0 ? "cantidad de controles" : "detalle del control \(discoveryPosition + 1)")
    finishDiscovery("La ruta HID++ rechazó \(stage), función \(String(format:"%04X",discoveryFeature)), índice \(query.featureIndex) (código \(code)); capacidad no determinada. No se modificó su configuración.")
   }
  case .payload(let payload):
   guard let first = payload.first else { finishDiscovery("Respuesta incompleta."); return }
   if query.featureIndex == 0 {
    store.keyboardDiscoveryTrace[target.key,default:[]].append("Búsqueda completada: índice recibido \(first).")
    if first == 0 {
     if discoveryFeature == 0x1b04 { discoveryFeature = 0x1b00; sendFeature(index:0,function:0,parameters:[0x1b,0x00]) }
     else { finishDiscovery("El teclado no declara las funciones de controles 1B04 ni 1B00. La sustitución por esta ruta no está disponible.") }
     return
    }
    discoveryIndex = first; sendFeature(index:first,function:0,parameters:[])
   } else if query.function == 0 {
    guard first <= 64 else { finishDiscovery("Catálogo fuera del límite de lectura (64 controles)."); return }
    discoveryCount = first
    guard first > 0 else { finishDiscovery("La función declarada no expone controles."); return }
    sendFeature(index:discoveryIndex,function:1,parameters:[0])
   } else {
    let control = discoveryFeature == 0x1b04 ? KeyboardControlInfo.parseV4(payload) : KeyboardControlInfo.parseV1(payload)
    guard let control, control.cid != 0 else { finishDiscovery("Descriptor de control incompleto; se conservan sólo los datos recibidos."); return }
    store.keyboardControls[target.key,default:[]].append(control)
    discoveryPosition += 1
    if discoveryPosition < discoveryCount { sendFeature(index:discoveryIndex,function:1,parameters:[discoveryPosition]) }
    else {
     let count = store.keyboardControls[target.key]?.filter(\.isDivertable).count ?? 0
     store.keyboardCatalogs[target.key] = KeyboardFeatureCatalog(endpoint:target.endpoint,slot:target.slot,wirelessID:target.wirelessID,featureID:discoveryFeature,featureIndex:discoveryIndex,controls:store.keyboardControls[target.key] ?? [])
     finishDiscovery("Lectura completada: \(discoveryCount) controles; \(count) declaran capacidad de desvío. Aún no se activó ningún reemplazo.")
    }
   }
  }
 }
 private func nextIdentityQuery() {
  identityTimer?.invalidate(); identityTimer = nil
  guard let store else { pendingIdentity = nil; identityQueue = []; unpairVerification = nil; return }
  guard store.capturing, store.receiverDiagnosticsEnabled, !identityQueue.isEmpty else { pendingIdentity = nil; identityQueue = []; unpairVerification = nil; store.identityWorkDidChange(); return }
  let query = identityQueue.removeFirst(); pendingIdentity = query
  let packet = query.request
  let result = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device,kIOHIDReportTypeOutput,0x10,$0.baseAddress!,packet.count) }
  if result != kIOReturnSuccess {
   if unpairVerification != nil { unpairVerification = nil; store.managementStatus[store.identity(device)] = "Falló la lectura de verificación. No se envió la desvinculación; requiere una nueva confirmación." }
   store.identificationErrors.append("\(store.identity(device)): consulta de lectura rechazada (\(result))"); store.identificationStatus = "No se pudo consultar una interfaz; revisa los errores de identificación"; pendingIdentity = nil; identityQueue = []; return
  }
  identityTimer = Timer.scheduledTimer(withTimeInterval:0.8,repeats:false) { [weak self] _ in
   guard let self else { return }
   self.store?.identificationTimeouts += 1
   if self.unpairVerification != nil {
    self.unpairVerification = nil
    if let store = self.store { store.managementStatus[store.identity(self.device)] = "No se pudo verificar la identidad actual. No se envió la desvinculación." }
   }
   self.pendingIdentity = nil; self.nextIdentityQuery()
  }
 }
 func receive(reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, count: CFIndex) {
  guard let store else { return }
  let metadata = String(format:"ID %02X · longitud %ld",reportID,count)
  store.receiverReportCounts[metadata,default:0] += 1
  // ID10 and all unknown reports receive aggregate ID/length counting only.
  let expected: Int
  switch reportID { case 0x10: expected=7; case 0x11: expected=20; case 0x20: expected=15; case 0x21: expected=32; default: store.receiverIgnoredCount += 1; return }
  guard count == expected || count == expected - 1 else { store.receiverIgnoredCount += 1; return }
  let format: ReceiverReportBufferFormat = count == expected ? .reportIDPrefixed : .payloadOnly
  let ephemeral = Array(UnsafeBufferPointer(start:bytes,count:count))
  let normalized: [UInt8] = count == expected ? ephemeral : [UInt8(reportID)] + ephemeral
  if diversionController?.receive(normalized) == true { return }
  if let controller = diversionController {
   for (source,lease) in controller.activeSources() {
    guard let down = KeyboardDivertedButtons.decode(normalized,slot:lease.slot,featureIndex:lease.featureIndex) else { continue }
    if down.contains(lease.cid) { if keyboardHeld.insert(source).inserted { store.executeExclusive(source) } }
    else { keyboardHeld.remove(source) }
   }
  }
  if let query = pendingFeature, let reply = query.parse(normalized) {
   featureTimer?.invalidate(); featureTimer = nil; pendingFeature = nil
   DispatchQueue.main.async { [weak self] in self?.consumeFeature(reply,query:query) }
   return
  }
  if let command = pendingManagement, let reply = command.parseReply(normalized) {
   managementTimer?.invalidate(); managementTimer = nil; pendingManagement = nil
   switch reply {
   case .accepted: store.managementFinished(endpoint:store.identity(device),command:command,accepted:true,message:"Orden aceptada por el receptor. Actualizando inventario…")
   case .rejected(let code): store.managementFinished(endpoint:store.identity(device),command:command,accepted:false,message:"El receptor rechazó la orden (HID++ \(code)).")
   }
   return
  }
  if let notification = ReceiverPairingNotification.parse(normalized) {
   store.recordPairingNotification(notification,endpoint:store.identity(device))
   return
  }
  if let query = pendingIdentity, let reply = query.parse(normalized) {
   identityTimer?.invalidate(); identityTimer = nil; pendingIdentity = nil
   store.recordQueriedIdentity(query:query,reply:reply,device:device)
   if let verification = unpairVerification {
    unpairVerification = nil; identityQueue = []
    guard reply.wirelessID == verification.wpid, query.slot == verification.slot else { store.managementStatus[store.identity(device)] = "La identidad cambió. No se envió la desvinculación."; return }
    sendManagement(.unpair(slot:verification.slot)); return
   }
   DispatchQueue.main.async { [weak self] in self?.nextIdentityQuery() }
   return
  }
  if (reportID == 0x20 || reportID == 0x21), normalized.count >= 3,
     (1...6).contains(normalized[1]), [UInt8(0x40),0x41,0x42].contains(normalized[2]) {
   store.invalidateIdentity(endpoint:store.identity(device),slot:normalized[1])
  }

  if let identity = ReceiverReportDecoder.decodeM570Identity(reportID:reportID,data:ephemeral,format:format) {
   store.recordReceiverIdentity(identity,device:device); return
  }
  if let mouse = ReceiverReportDecoder.decodeDJMouse(reportID:reportID,data:ephemeral,format:format,previousMasks:djMasks) {
   djMasks[mouse.slot] = mouse.extraButtonsMask
   store.recordReceiverButtons(mouse,device:device,route:.djMouse); return
  }
  if let candidate = ReceiverReportDecoder.decodeSynthetic1B04(reportID:reportID,data:ephemeral,format:format,previousMasks:featureMasks) {
   featureMasks[candidate.slot] = candidate.extraButtonsMask
   store.recordReceiverButtons(candidate,device:device,route:.synthetic1B04); return
  }
  store.receiverIgnoredCount += 1
 }
 deinit {
  featureTimer?.invalidate()
  managementTimer?.invalidate()
  identityTimer?.invalidate()
  IOHIDDeviceRegisterInputReportCallback(device,buffer,32,nil,nil)
  IOHIDDeviceClose(device,IOOptionBits(kIOHIDOptionsTypeNone))
  buffer.deinitialize(count:32); buffer.deallocate()
 }
}

struct DeviceInfo: Identifiable {
 let id: String
 let name: String
 let detail: String
 let capabilities: [String]
 let device: IOHIDDevice?
 var usb: USBDeviceInfo? = nil
}
final class DeviceStore: ObservableObject {
 let audio = DigitalAudioController()
 var hasBackgroundActivity:Bool { capturing || audio.isProcessing || audio.hasRestorationObligations }
 private var audioObservation:AnyCancellable?
 private var sleepObservation:NSObjectProtocol?
 @Published var devices: [DeviceInfo] = []
 @Published var usbDevices: [USBDeviceInfo] = []
 @Published var usbInventoryWarning: String?
 var sidebarDevices: [DeviceInfo] {
  let connectedPrefixes = Set(usbDevices.compactMap(\.hidPrefix))
  let identified = verifiedIdentities.values.filter { connectedPrefixes.contains($0.endpoint.components(separatedBy:":").prefix(3).joined(separator:":")) }.sorted { $0.key < $1.key }
  let identifiedReceivers = Set(identified.map { $0.endpoint.components(separatedBy:":").prefix(3).joined(separator:":") })
  let physicalPrefixes = Set(usbDevices.compactMap(\.hidPrefix))
  var rows = devices.filter { device in
   let prefix = device.id.components(separatedBy:":").prefix(3).joined(separator:":")
   return !physicalPrefixes.contains(prefix) && !identifiedReceivers.contains(prefix)
  }.map { device in
   let isCamera = device.id.hasPrefix("camera:")
   let virtualMouse = device.name == "LogiVirtualHIDDevice"
   let name = isCamera && device.name.hasPrefix("USB Camera VID:") ? "Cámara USB · vídeo" : (virtualMouse ? "Entrada virtual de ratón" : device.name)
   return DeviceInfo(id:device.id,name:name,detail:isCamera ? "Interfaz de vídeo" : (virtualMouse ? "Interfaz HID virtual" : "Interfaz HID"),capabilities:device.capabilities,device:device.device)
  }
  for usb in usbDevices {
   let prefix = usb.hidPrefix
   let interfaces = devices.filter { device in prefix.map { device.id.hasPrefix($0 + ":") } ?? false }.sorted{$0.id < $1.id}
   let primary = interfaces.first(where:{$0.id.hasSuffix(":1:2")}) ?? interfaces.first(where:{!$0.capabilities.isEmpty}) ?? interfaces.first
   let pairedReceiver = prefix.map { identifiedReceivers.contains($0) } ?? false
   let displayName = pairedReceiver ? "Receptor Unifying" : (usb.name == "Dispositivo USB" ? usb.category : (usb.name == "AppleUSBXHCI Root Hub Simulation" ? "Hub raíz del sistema" : usb.name))
   rows.append(DeviceInfo(id:pairedReceiver ? usb.id : (primary?.id ?? usb.id),name:displayName,detail:pairedReceiver ? "Receptor USB · dispositivos identificados por separado" : usb.category,capabilities:primary?.capabilities ?? [],device:pairedReceiver ? nil : primary?.device,usb:usb))
  }
  for item in identified {
   let prefix = item.endpoint.components(separatedBy:":").prefix(3).joined(separator:":")
   let transport = devices.first { $0.id == prefix + ":1:2" }
   rows.append(DeviceInfo(id:item.key,name:item.displayName,detail:item.categoryName + (capturing ? " · Identificado por HID++" : " · Identificación guardada · pausado"),capabilities:transport?.capabilities ?? [],device:transport?.device))
  }
  rows += audio.outputs.map { DeviceInfo(id:"audio|" + $0.id,name:$0.name,detail:"Salida de audio · control digital Korda",capabilities:[],device:nil) }
  return rows.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
 }
 func transportID(for selection: String) -> String {
  guard let item = verifiedIdentities[selection] else { return selection }
  return item.endpoint.components(separatedBy:":").prefix(3).joined(separator:":") + ":1:2"
 }
 func logicalSelection(for source: String, page: UInt32? = nil) -> String? {
  if source.hasPrefix("keyboard|") {
   return verifiedIdentities.values.first { source.hasPrefix("keyboard|endpoint=\($0.endpoint)|slot=\($0.slot)|wpid=\(String(format:"%04X",$0.wirelessID))|") }?.key
  }
  if source.hasPrefix("receiver|") {
   return verifiedIdentities.values.first { source.hasPrefix("receiver|endpoint=\($0.endpoint)|slot=\($0.slot)|") }?.key
  }
  let components = source.split(separator:":")
  let sourcePage = page ?? (components.count >= 7 ? UInt32(components[components.count-2]) : nil)
  guard sourcePage == 7 || sourcePage == 12 else { return nil }
  let prefix = source.components(separatedBy:":").prefix(3).joined(separator:":")
  let candidates = verifiedIdentities.values.filter { $0.kind == 1 && $0.endpoint.components(separatedBy:":").prefix(3).joined(separator:":") == prefix }
  return candidates.count == 1 ? candidates.first?.key : nil
 }
 func keyboardRouteIsUnique(_ item: HIDDeviceIdentity) -> Bool {
  let prefix = item.endpoint.components(separatedBy:":").prefix(3).joined(separator:":")
  return verifiedIdentities.values.filter { $0.kind == 1 && $0.endpoint.hasPrefix(prefix + ":") }.count == 1
 }
 func presentationSelection(for source:String,page:UInt32? = nil) -> String? {
  if let logical = logicalSelection(for:source,page:page) { return logical }
  let prefix = source.components(separatedBy:":").prefix(3).joined(separator:":")
  return sidebarDevices.first(where:{$0.usb?.hidPrefix == prefix})?.id ?? sidebarDevices.first(where:{source.hasPrefix($0.id + ":")})?.id
 }
 func deviceLabel(for source: String) -> String { presentationSelection(for:source).flatMap { key in sidebarDevices.first(where:{$0.id == key})?.name } ?? "Dispositivo / receptor" }
 func chooseControl(_ source: String) { lastSource = source; learnedEndpoint = selected ?? ""; learning = false; lastEvent = Mapping(source:source,action:"",keyCode:0,modifiers:0).controlLabel }
 func standardRouteIsUsable(_ source: String) -> Bool {
  guard source.hasPrefix("1133:50475:") else { return true }
  if managementSuspendedEndpoints.contains(where:{source.hasPrefix($0.components(separatedBy:":").prefix(3).joined(separator:":") + ":")}) { return false }
  guard !source.hasPrefix("receiver|"), let key = logicalSelection(for:source), let item = verifiedIdentities[key] else { return false }
  return keyboardRouteIsUnique(item)
 }
 @discardableResult func editMapping(_ mapping: Mapping) -> Bool {
  guard let target = presentationSelection(for:mapping.source) else { actionStatus = "Reanuda e identifica el dispositivo antes de editar esta asignación."; return false }
  selected = target; chooseControl(mapping.source); return true
 }
 @Published var selected: String?
 @Published var capturing = false
 @Published var learning = true
 @Published var lastSource = ""
 @Published var learnedEndpoint = ""
 @Published var receiverProfiles: [ReceiverMappingProfile] = []
 @Published var verifiedIdentities: [String:HIDDeviceIdentity] = [:]
 @Published var identificationStatus = "Identificación HID++ pendiente"
 @Published var identificationTimeouts = 0
 @Published var identificationErrors: [String] = []
 @Published var managementStatus: [String:String] = [:]
 @Published var keyboardDiscoveryStatus: [String:String] = [:]
 @Published var keyboardDiscoveryTrace: [String:[String]] = [:]
 @Published var keyboardControls: [String:[KeyboardControlInfo]] = [:]
 @Published var keyboardCatalogs: [String:KeyboardFeatureCatalog] = [:]
 @Published var exclusiveStatus = ""
 @Published var isRestoring = false
 private var stopCompletions: [(Bool)->Void] = []
 private var exclusiveDiscoveryAttempted = Set<String>()
 private var exclusiveActivationAttempted = Set<String>()
 var hasExclusiveObligations: Bool { receiverRegistrations.contains{$0.diversionController?.hasRestorationObligations == true || $0.diversionController?.busy == true} }
 @Published var pairingDeadlines: [String:Date] = [:]
 private var managementSuspendedEndpoints = Set<String>()
 private var pairingTimers: [String:Timer] = [:]
 private var identityRefreshRequested = false
 var receiverEndpoints: [String] { devices.filter { $0.device.map(KnownReceiverReportLayout.accepts) ?? false }.map(\.id).sorted() }
 func receiverName(_ endpoint:String) -> String { "Receptor \((receiverEndpoints.firstIndex(of:endpoint) ?? 0) + 1)" }
 func pairedDevices(_ endpoint:String) -> [HIDDeviceIdentity] { verifiedIdentities.values.filter{$0.endpoint == endpoint}.sorted{$0.slot < $1.slot} }
 func canManageReceiver(_ endpoint:String) -> Bool {
  !isRestoring && capturing && receiverDiagnosticsEnabled && receiverRegistrations.contains { identity($0.device) == endpoint && !$0.identityBusy && !$0.featureBusy && $0.pendingManagement == nil && $0.diversionController?.busy != true && $0.diversionController?.hasRestorationObligations != true }
 }
 func discoverKeyboard(_ target:HIDDeviceIdentity) {
  guard target.kind == 1, [UInt16(0x4076),0x4024].contains(target.wirelessID), verifiedIdentities[target.key]?.wirelessID == target.wirelessID, canManageReceiver(target.endpoint), pairingDeadlines[target.endpoint] == nil, let registration = receiverRegistrations.first(where:{identity($0.device) == target.endpoint}) else { keyboardDiscoveryStatus[target.key] = "Espera a que termine la identificación y comprueba que el teclado esté encendido."; return }
  registration.discoverKeyboard(target)
 }
 func prepareReceiverManagement() {
  if !capturing { start() }
  guard capturing else { return }
  if !receiverDiagnosticsEnabled { receiverDiagnosticsEnabled = true }
  identifyDevices()
 }
 func manageReceiver(_ endpoint:String, command:ReceiverManagementCommand, expectedWPID:UInt16? = nil) {
  guard canManageReceiver(endpoint), let registration = receiverRegistrations.first(where:{identity($0.device) == endpoint}) else { managementStatus[endpoint] = "Autoriza Korda, inicia captura y espera a que termine la identificación."; return }
  if command == .openPairing, pairedDevices(endpoint).count >= 6 { managementStatus[endpoint] = "El receptor tiene seis posiciones ocupadas. Quita un dispositivo antes de añadir otro."; return }
  if let slot = command.slot {
   guard let expectedWPID, let target = verifiedIdentities[endpoint + "|slot=\(slot)"], target.wirelessID == expectedWPID else { managementStatus[endpoint] = "La identidad seleccionada ya no coincide. Actualiza el inventario."; return }
   managementSuspendedEndpoints.insert(endpoint)
   managementStatus[endpoint] = "Verificando identidad de \(target.displayName) antes de desvincular…"
   registration.verifyAndUnpair(slot:slot,wpid:expectedWPID)
  } else {
   managementSuspendedEndpoints.insert(endpoint)
   if command == .openPairing { watchPairingWindow(endpoint) }
   managementStatus[endpoint] = "Enviando \(command.label)…"
   registration.sendManagement(command)
  }
 }
 private func watchPairingWindow(_ endpoint:String) {
  pairingDeadlines[endpoint] = Date().addingTimeInterval(60)
  pairingTimers[endpoint]?.invalidate()
  pairingTimers[endpoint] = Timer.scheduledTimer(withTimeInterval:61,repeats:false) { [weak self] _ in
   guard let self else { return }; self.pairingDeadlines.removeValue(forKey:endpoint)
   self.managementStatus[endpoint] = "Finalizó el plazo de emparejamiento. Consultando dispositivos; la detección confirma el resultado."
   self.identifyDevices()
  }
 }
 func managementFinished(endpoint:String,command:ReceiverManagementCommand,accepted:Bool,message:String) {
  managementStatus[endpoint] = message
  if accepted, command == .openPairing {
   managementStatus[endpoint] = pairingDeadlines[endpoint] != nil ? "Orden de emparejamiento aceptada. Apaga y enciende sólo el dispositivo que quieras añadir. Plazo: 60 segundos." : "Orden aceptada; el receptor ya informó el cierre del emparejamiento. Actualiza el inventario."
  } else {
   if accepted, command == .closePairing { pairingDeadlines.removeValue(forKey:endpoint); pairingTimers[endpoint]?.invalidate() }
   if accepted, let slot = command.slot {
    verifiedIdentities.removeValue(forKey:endpoint + "|slot=\(slot)")
    for index in receiverProfiles.indices where receiverProfiles[index].endpoint == endpoint && receiverProfiles[index].slot == slot { receiverProfiles[index].enrolled = false }
    persistReceiverProfiles(); receiverMappingRuntime.reset()
   }
   DispatchQueue.main.async { [weak self] in self?.identifyDevices() }
  }
 }
 func recordPairingNotification(_ notification:ReceiverPairingNotification,endpoint:String) {
  managementStatus[endpoint] = notification.error == 0 ? (notification.open ? "El receptor informa: emparejamiento abierto." : "El receptor informa: emparejamiento cerrado. Actualizando inventario…") : "Error de emparejamiento del receptor: \(notification.error)."
  if !notification.open {
   pairingDeadlines.removeValue(forKey:endpoint); pairingTimers[endpoint]?.invalidate()
   DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { [weak self] in self?.identifyDevices() }
  }
 }
 @Published var actionStatus = ""
 private var receiverMappingRuntime = ReceiverMappingRuntime()
 @Published var lastEvent = "Sin eventos"
 @Published var recentEvents: [String] = []
 @Published var status = ""
 @Published var mappings: [Mapping] = []
 @Published var enabled = false
 @Published var rawDiagnosticsEnabled = false { didSet { configureRawDiagnostics() } }
 @Published var rawReportCount = 0
 @Published var rawRejectedCount = 0
 @Published var rawButtonCount = 0
 @Published var standardButtonCount = 0
 @Published var rawEvents: [String] = []
 @Published var rawInterfaceCount = 0
 private var rawRegistrations: [MouseReportRegistration] = []
 @Published var receiverDiagnosticsEnabled = false { didSet {
  if !receiverDiagnosticsEnabled && hasExclusiveObligations { receiverDiagnosticsEnabled = true; exclusiveStatus = "Pausa Korda para restaurar las teclas antes de cerrar esta conexión."; return }
  configureReceiverDiagnostics()
 } }
 @Published var receiverInterfaceCount = 0
 @Published var receiverOpenResults: [String] = []
 @Published var receiverReportCounts: [String:Int] = [:]
 @Published var receiverAcceptedCounts: [String:Int] = [:]
 @Published var receiverIgnoredCount = 0
 @Published var receiverEvents: [String] = []
 @Published var observedM570Slots: [String] = []
 private var receiverRegistrations: [ReceiverReportRegistration] = []
 private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
 private var pressed = Set<String>()
 private var timer: Timer?
 init() {
  audioObservation = audio.objectWillChange.receive(on:DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }
  sleepObservation = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in self?.stop() }
  if let data = UserDefaults.standard.data(forKey: "mappings"), let saved = try? JSONDecoder().decode([Mapping].self, from: data) { mappings = saved }
  if let data = UserDefaults.standard.data(forKey:"receiverProfiles"), let saved = try? JSONDecoder().decode([ReceiverMappingProfile].self,from:data) { receiverProfiles = saved.map { original in var profile = original; if profile.verifiedWirelessID == nil { profile.enrolled = false }; return profile } }
  IOHIDManagerSetDeviceMatching(manager, nil)
  IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
   guard let context, result == kIOReturnSuccess else { return }
   let store = Unmanaged<DeviceStore>.fromOpaque(context).takeUnretainedValue()
   store.receive(value)
  }, Unmanaged.passUnretained(self).toOpaque())
  IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
  refresh()
  timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
 }
 func property(_ device: IOHIDDevice, _ key: String) -> String { IOHIDDeviceGetProperty(device, key as CFString).map { String(describing: $0) } ?? "—" }
 func identity(_ device: IOHIDDevice) -> String {
  // A receiver can expose several interfaces; never infer the paired model from these IDs.
  [kIOHIDVendorIDKey, kIOHIDProductIDKey, kIOHIDLocationIDKey, kIOHIDPrimaryUsagePageKey, kIOHIDPrimaryUsageKey].map { property(device, $0) }.joined(separator: ":")
 }
 func refresh() {
  audio.refresh()
  let usbSnapshot = USBInventory.snapshot()
  usbDevices = usbSnapshot.devices; usbInventoryWarning = usbSnapshot.warning
  let hid = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
  var rows = hid.map { device -> DeviceInfo in
   let elements = (IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement]) ?? []
   let controls = Set(elements.filter { CapturePolicy.allows(page: IOHIDElementGetUsagePage($0), usage: IOHIDElementGetUsage($0)) }.map {
    CapturePolicy.label(page: IOHIDElementGetUsagePage($0), usage: IOHIDElementGetUsage($0)) + String(format: " · rango %ld…%ld", IOHIDElementGetLogicalMin($0), IOHIDElementGetLogicalMax($0))
   }).sorted()
   return DeviceInfo(id: identity(device), name: property(device, kIOHIDProductKey), detail: "HID · VID \(property(device, kIOHIDVendorIDKey)) · PID \(property(device, kIOHIDProductIDKey)) · \(property(device, kIOHIDTransportKey))", capabilities: controls, device: device)
  }
  let cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified).devices
  rows += cameras.map { DeviceInfo(id: "camera:" + $0.uniqueID, name: $0.localizedName, detail: "Cámara · inventario sin abrir vídeo", capabilities: ["La configuración UVC de esta cámara aún no está implementada."], device: nil) }
  var seen = Set<String>()
  devices = rows.filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
  let input = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
  status = "Monitorización: \(input == kIOHIDAccessTypeGranted ? "autorizada" : "sin autorización confirmada") · Accesibilidad: \(AXIsProcessTrusted() ? "autorizada" : "sin autorización")"
 }
 func start() {
  let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  capturing = result == kIOReturnSuccess
  lastEvent = capturing ? "Pulsa un botón; se seleccionará automáticamente la interfaz emisora" : "No se pudo abrir HID: \(result)"
 }
 func resumeBackground() {
  guard !isRestoring, !hasExclusiveObligations else { exclusiveStatus = "Completa primero la restauración de las teclas."; return }
  start()
  guard capturing else { return }
  learning = false
  enabled = true
  exclusiveDiscoveryAttempted = []; exclusiveActivationAttempted = []
  receiverDiagnosticsEnabled = receiverProfiles.contains(where: \.enrolled) || mappings.contains{$0.source.hasPrefix("keyboard|") && $0.isEnabled}
  UserDefaults.standard.set(true, forKey:"backgroundAssignmentsEnabled")
 }
 func pauseBackground() {
  stop()
  UserDefaults.standard.set(false, forKey:"backgroundAssignmentsEnabled")
 }
 func stop(completion: ((Bool)->Void)? = nil) {
  if let completion { stopCompletions.append(completion) }
  enabled = false; learning = false
  guard audio.stop() else {
   exclusiveStatus = audio.status
   let callbacks = stopCompletions;stopCompletions.removeAll();callbacks.forEach{$0(false)}
   return
  }
  if isRestoring { return }
  let controllers = receiverRegistrations.compactMap(\.diversionController).filter{$0.hasRestorationObligations || $0.busy}
  guard !controllers.isEmpty else { finishStop(); return }
  isRestoring = true; exclusiveStatus = "Restaurando las funciones originales antes de pausar…"
  var remaining = controllers.count; var allOK = true
  for controller in controllers {
   controller.restoreAll { [weak self] ok,_ in
    guard let self else { return }
    allOK = allOK && ok; remaining -= 1
    guard remaining == 0 else { return }
    self.isRestoring = false
    if allOK && !self.hasExclusiveObligations { self.exclusiveStatus = "Funciones originales restauradas y verificadas."; self.finishStop() }
    else {
     self.exclusiveStatus = "No se confirmó la restauración. Enciende o reconecta el teclado y vuelve a pausar o salir. Korda conserva la conexión pendiente."
     let callbacks = self.stopCompletions; self.stopCompletions = []; callbacks.forEach{$0(false)}
    }
   }
  }
 }
 private func finishStop() {
  receiverMappingRuntime = ReceiverMappingRuntime(); receiverDiagnosticsEnabled = false; receiverRegistrations.removeAll(); receiverInterfaceCount = 0; rawDiagnosticsEnabled = false; rawRegistrations.removeAll(); rawInterfaceCount = 0; capturing = false; enabled = false; pressed.removeAll(); IOHIDManagerClose(manager, 0)
  let callbacks = stopCompletions; stopCompletions = []; callbacks.forEach{$0(true)}
 }
 func configureReceiverDiagnostics() {
  if hasExclusiveObligations { exclusiveStatus = "Pausa Korda para restaurar las teclas antes de reconstruir la conexión."; return }
  receiverMappingRuntime.reset()
  receiverRegistrations.removeAll(); receiverInterfaceCount = 0; receiverOpenResults = []
  guard receiverDiagnosticsEnabled, capturing else { return }
  verifiedIdentities.removeAll()
  let hid = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
  for device in hid where KnownReceiverReportLayout.accepts(device) {
   let result = IOHIDDeviceOpen(device,IOOptionBits(kIOHIDOptionsTypeNone))
   receiverOpenResults.append("\(identity(device)) · apertura no exclusiva: \(result)")
   if result == kIOReturnSuccess { receiverRegistrations.append(ReceiverReportRegistration(device:device,store:self)) }
  }
  receiverInterfaceCount = receiverRegistrations.count
  if receiverProfiles.contains(where: \.enrolled) || mappings.contains(where:{$0.source.hasPrefix("keyboard|") && $0.isEnabled}) { identifyDevices() }
 }
 func identifyDevices() {
  guard capturing, receiverDiagnosticsEnabled, !receiverRegistrations.isEmpty else { identificationStatus = "Inicia la captura y la lectura del receptor para identificar dispositivos"; return }
  guard !receiverRegistrations.contains(where: { $0.identityBusy || $0.featureBusy || $0.pendingManagement != nil }) else { identityRefreshRequested = true; return }
  identityRefreshRequested = false
  verifiedIdentities.removeAll(); identificationTimeouts = 0; identificationErrors = []
  keyboardControls = [:]; keyboardCatalogs = [:]; keyboardDiscoveryStatus = [:]; keyboardDiscoveryTrace = [:]
  identificationStatus = "Consultando nombre, tipo e identificador de posiciones emparejadas…"
  for registration in receiverRegistrations { registration.identifyDevices() }
 }
 func identityWorkDidChange() {
  guard !receiverRegistrations.contains(where: { $0.identityBusy || $0.featureBusy }) else { return }
  if identityRefreshRequested, !receiverRegistrations.contains(where:{$0.pendingManagement != nil}) {
   identityRefreshRequested = false
   DispatchQueue.main.async { [weak self] in self?.identifyDevices() }
   return
  }
  for endpoint in Array(managementSuspendedEndpoints) where pairingDeadlines[endpoint] == nil && !receiverRegistrations.contains(where:{identity($0.device) == endpoint && $0.pendingManagement != nil}) { managementSuspendedEndpoints.remove(endpoint) }
  identificationStatus = "Consulta finalizada: \(verifiedIdentities.count) identidades; \(identificationTimeouts) consultas sin respuesta. Las posiciones vacías pueden no responder."
  resumeExclusiveMappingsIfPossible()
 }
 func invalidateIdentity(endpoint: String, slot: UInt8) {
  keyboardControls.removeValue(forKey:endpoint + "|slot=\(slot)")
  keyboardCatalogs.removeValue(forKey:endpoint + "|slot=\(slot)")
  keyboardDiscoveryStatus.removeValue(forKey:endpoint + "|slot=\(slot)")
  keyboardDiscoveryTrace.removeValue(forKey:endpoint + "|slot=\(slot)")
  verifiedIdentities.removeValue(forKey:endpoint + "|slot=\(slot)")
  if receiverProfiles.contains(where:{$0.enrolled && $0.endpoint == endpoint && $0.slot == slot}) {
   DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { [weak self] in self?.identifyDevices() }
  }
 }
 func recordQueriedIdentity(query: HIDIdentityQuery, reply: HIDIdentityReply, device: IOHIDDevice) {
  let endpoint = identity(device), key = endpoint + "|slot=\(query.slot)"
  if let wpid = reply.wirelessID, let kind = reply.kind {
   verifiedIdentities[key] = HIDDeviceIdentity(endpoint:endpoint,slot:query.slot,wirelessID:wpid,kind:kind,name:nil,checkedAt:Date())
  } else if let name = reply.name, var current = verifiedIdentities[key] {
   current.name = name; verifiedIdentities[key] = current
  }
  identificationStatus = "\(verifiedIdentities.count) identidades HID++ recibidas. Una posición emparejada puede estar apagada."
 }

 func recordReceiverIdentity(_ observation: ReceiverIdentity, device: IOHIDDevice) {
  let key = "\(identity(device)) · slot \(observation.slot)"
  if !observedM570Slots.contains(key) { observedM570Slots.append(key) }
 }
 func enrollReceiverProfile(_ profile: ReceiverMappingProfile, enabled: Bool) {
  guard let index = receiverProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
  if enabled {
   guard let identified = verifiedIdentities[profile.endpoint + "|slot=\(profile.slot)"] else { identificationStatus = "Identifica este dispositivo mediante HID++ antes de habilitar la ruta"; return }
   receiverProfiles[index].verifiedWirelessID = identified.wirelessID
  }
  receiverProfiles[index].enrolled = enabled
  receiverMappingRuntime.reset()
  if !enabled && lastSource.hasPrefix(profile.id + "|button=") { lastSource = ""; learnedEndpoint = "" }
  persistReceiverProfiles()
 }
 func confirmReceiverButtonLabels(_ profile: ReceiverMappingProfile, confirmed: Bool) {
  guard let index = receiverProfiles.firstIndex(where:{$0.id == profile.id}) else { return }
  receiverProfiles[index].buttonLabelsConfirmed = confirmed
  persistReceiverProfiles()
 }
 func persistReceiverProfiles() {
  if let data = try? JSONEncoder().encode(receiverProfiles) { UserDefaults.standard.set(data,forKey:"receiverProfiles") }
 }
 func recordReceiverButtons(_ observation: ReceiverButtonResult, device: IOHIDDevice, route: ReceiverMappingRoute) {
  let endpoint = identity(device)
  let observedProfile = ReceiverMappingProfile(endpoint:endpoint,slot:observation.slot,route:route)
  if !receiverProfiles.contains(where:{ $0.id == observedProfile.id }) { receiverProfiles.append(observedProfile) }
  let profile = receiverProfiles.first(where:{$0.id == observedProfile.id}) ?? observedProfile
  let key = "\(endpoint) · slot \(observation.slot)"
  receiverAcceptedCounts[key + " · " + route.label,default:0] += 1
  let model = observedM570Slots.contains(key) ? "M570 identificado por notificación" : "modelo no identificado"
  receiverMappingRuntime.listening = capturing && receiverDiagnosticsEnabled
  receiverMappingRuntime.executionEnabled = enabled
  let enrolled = Set(receiverProfiles.filter { profile in
   let current = verifiedIdentities[profile.endpoint + "|slot=\(profile.slot)"]
   return !managementSuspendedEndpoints.contains(profile.endpoint) && profile.permitsIdentifiedDevice(current?.wirelessID)
  }.map(\.id))
  for change in observation.changes {
   let timestamp = Date().formatted(date:.omitted,time:.standard)
   let direction = change.isDown ? "pulsado" : "soltado"
   receiverEvents.insert("\(timestamp) · \(key) · \(route.label) · \(model) · \(profile.buttonLabel(change.button)) \(direction)",at:0)
   let decision = receiverMappingRuntime.consume(profile:profile,button:change.button,isDown:change.isDown,enrolled:enrolled)
   if decision.learn && learning {
    lastSource = decision.source; let target = logicalSelection(for:decision.source) ?? endpoint; learnedEndpoint = target; selected = target
    lastEvent = "\(timestamp) · \(profile.buttonLabel(change.button)) · slot \(profile.slot) · \(route.label)"
    recentEvents.insert(lastEvent + " · " + endpoint,at:0)
    recentEvents = Array(recentEvents.prefix(10))
   }
   if decision.execute, let mapping = mappings.first(where:{$0.source == decision.source && $0.isEnabled}) { perform(mapping) }
  }
  receiverEvents = Array(receiverEvents.prefix(10))
 }
 func configureRawDiagnostics() {
  rawRegistrations.removeAll(); rawInterfaceCount = 0
  guard rawDiagnosticsEnabled, capturing else { return }
  let hid = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
  rawRegistrations = hid.filter { KnownMouseReportLayout.accepts($0) }.map { MouseReportRegistration(device: $0, store: self) }
  rawInterfaceCount = rawRegistrations.count
 }
 func recordRawButton(_ change: MouseButtonChange, device: IOHIDDevice) {
  rawButtonCount += 1
  let timestamp = Date().formatted(date: .omitted, time: .standard)
  let direction = change.isDown ? "pulsado" : "soltado"
  rawEvents.insert("\(timestamp) · informe2 · botón \(change.button) \(direction) · \(identity(device))", at: 0)
  rawEvents = Array(rawEvents.prefix(10))
  // Diagnostic only: never use this path to create or execute a mapping.
 }
 func receive(_ value: IOHIDValue) {
  guard capturing else { return }
  let element = IOHIDValueGetElement(value)
  let page = IOHIDElementGetUsagePage(element), usage = IOHIDElementGetUsage(element)
  guard CapturePolicy.allows(page: page, usage: usage) else { return }
  let device = IOHIDElementGetDevice(element)
  let deviceID = identity(device)
  let source = "\(deviceID):\(page):\(usage)"
  if IOHIDValueGetIntegerValue(value) == 0 { pressed.remove(source); return }
  guard pressed.insert(source).inserted else { return }
  standardButtonCount += 1
  if learning {
  lastSource = source
  let target = presentationSelection(for:source,page:page) ?? deviceID
  learnedEndpoint = target
  selected = target
  let timestamp = Date().formatted(date: .omitted, time: .standard)
  lastEvent = "\(timestamp) · \(property(device, kIOHIDProductKey)) · \(CapturePolicy.label(page: page, usage: usage))"
  recentEvents.insert(lastEvent + " · " + deviceID, at: 0)
  recentEvents = Array(recentEvents.prefix(10))
  }
  if enabled, standardRouteIsUsable(source), let mapping = mappings.first(where: { $0.source == source && $0.isEnabled }) { perform(mapping) }
 }
 func save(action: String, keyCode: UInt16, modifiers: UInt64, application:ApplicationTarget? = nil,audioOutputUID:String? = nil) {
  if action == "launchApplication", application == nil { actionStatus = "Elige una aplicación antes de guardar."; return }
  if ["digitalVolumeUp","digitalVolumeDown","digitalMute"].contains(action), audioOutputUID?.isEmpty != false { actionStatus = "Elige una salida de audio."; return }
  if action == "original" { restoreSelectedOriginal(); return }
  guard !lastSource.isEmpty, selected == learnedEndpoint else { actionStatus = "Selecciona primero el control que quieres configurar."; return }
  if lastSource.hasPrefix("keyboard|") { actionStatus = "Este control tiene un reemplazo exclusivo. Restablece su función original antes de crear una acción adicional."; return }
  if !lastSource.hasPrefix("receiver|"), !standardRouteIsUsable(lastSource) { actionStatus = "La ruta del teclado no está identificada o la comparten varios teclados."; return }
  if lastSource.hasPrefix("receiver|"), !receiverProfiles.contains(where:{$0.enrolled && lastSource.hasPrefix($0.id + "|button=")}) { actionStatus = "La ruta propietaria aún no está autorizada para asignaciones. Revísala en Ajustes → Diagnósticos."; return }
  if let previous = selectedMapping,previous.source.hasPrefix("keyboard|"),previous.source != lastSource {
   let source = lastSource
   restoreMapping(previous) { [weak self] ok in
    guard let self,ok else { return };self.mappings.removeAll{$0.id == previous.id}
    self.savePlainMapping(source:source,action:action,keyCode:keyCode,modifiers:modifiers,application:application,audioOutputUID:audioOutputUID)
   };return
  }
  savePlainMapping(source:lastSource,action:action,keyCode:keyCode,modifiers:modifiers,application:application,audioOutputUID:audioOutputUID)
 }
 private func savePlainMapping(source:String,action:String,keyCode:UInt16,modifiers:UInt64,application:ApplicationTarget? = nil,audioOutputUID:String? = nil) {
  let updating = mappings.contains(where:{$0.source == source})
  let wasEnabled = mappings.first(where:{$0.source == source})?.isEnabled ?? true
  mappings.removeAll { $0.source == source }
  mappings.append(Mapping(source: source, action: action, keyCode: keyCode, modifiers: modifiers,isEnabled:wasEnabled,application:application,audioOutputUID:audioOutputUID))
  learning = false
  persist()
  actionStatus = updating ? "Asignación actualizada." : "Asignación guardada."
 }
 private func exclusiveCandidate() -> (KeyboardFeatureCatalog,KeyboardControlInfo,ReceiverReportRegistration)? {
  guard let selected, let catalog = keyboardCatalogs[selected], verifiedIdentities[selected]?.wirelessID == catalog.wirelessID else { return nil }
  let matched = catalog.controls.first { control in
   guard let usage = control.consumerUsage,catalog.control(forUsage:usage)?.cid == control.cid else { return false }
   return lastSource == transportID(for:selected) + ":12:\(usage)" || lastSource == exclusiveSource(catalog,control:control,usage:usage)
  }
  guard let control = matched,
        let registration = receiverRegistrations.first(where:{identity($0.device) == catalog.endpoint}),
        !registration.identityBusy,!registration.featureBusy,registration.pendingManagement == nil,registration.diversionController?.busy != true else { return nil }
  return (catalog,control,registration)
 }
 private func exclusiveSource(_ catalog:KeyboardFeatureCatalog,control:KeyboardControlInfo,usage:UInt32) -> String {
  "keyboard|endpoint=\(catalog.endpoint)|slot=\(catalog.slot)|wpid=\(String(format:"%04X",catalog.wirelessID))|cid=\(String(format:"%04X",control.cid))|usage=\(usage)"
 }
 var selectedMapping: Mapping? {
  if let direct = mappings.first(where:{$0.source == lastSource}) { return direct }
  guard let selected,let catalog = keyboardCatalogs[selected],verifiedIdentities[selected]?.wirelessID == catalog.wirelessID,
        let tail = lastSource.split(separator:":").last,let usage = UInt32(tail),lastSource == transportID(for:selected) + ":12:\(usage)",let control = catalog.control(forUsage:usage) else { return nil }
  return mappings.first(where:{$0.source == exclusiveSource(catalog,control:control,usage:usage)})
 }
 var canReplaceSelectedControl: Bool {
  guard !isRestoring else { return false }
  if lastSource.hasPrefix("keyboard|"),receiverRegistrations.contains(where:{$0.diversionController?.isActive(source:lastSource) == true}) { return true }
  return exclusiveCandidate() != nil && capturing && !isRestoring
 }
 func saveExclusive(action:String,keyCode:UInt16,modifiers:UInt64,application:ApplicationTarget? = nil,audioOutputUID:String? = nil) {
  if action == "launchApplication", application == nil { actionStatus = "Elige una aplicación antes de guardar."; return }
  if ["digitalVolumeUp","digitalVolumeDown","digitalMute"].contains(action), audioOutputUID?.isEmpty != false { actionStatus = "Elige una salida de audio."; return }
  if action == "original" { restoreSelectedOriginal(); return }
  guard !isRestoring,capturing,AXIsProcessTrusted(),keyCode <= 127 else { actionStatus = "Activa Korda y comprueba sus permisos antes de reemplazar una tecla."; return }
  if lastSource.hasPrefix("keyboard|"),receiverRegistrations.contains(where:{$0.diversionController?.isActive(source:lastSource) == true}) {
   let wasEnabled = mappings.first(where:{$0.source == lastSource})?.isEnabled ?? true
   mappings.removeAll{$0.source == lastSource};mappings.append(Mapping(source:lastSource,action:action,keyCode:keyCode,modifiers:modifiers,isEnabled:wasEnabled,application:application,audioOutputUID:audioOutputUID));persist();actionStatus = "Reemplazo actualizado.";return
  }
  guard let (catalog,control,registration) = exclusiveCandidate(),let controller = registration.diversionController,let usage = control.consumerUsage else { actionStatus = "Consulta la compatibilidad de este teclado en Ajustes → Diagnósticos. Sólo se reemplazan controles 1B04 que declaren desvío."; return }
  let source = exclusiveSource(catalog,control:control,usage:usage)
  let nativeSource = lastSource
  let lease = KeyboardDiversionLease(endpoint:catalog.endpoint,slot:catalog.slot,wirelessID:catalog.wirelessID,featureIndex:catalog.featureIndex,cid:control.cid,capabilityFlags:control.flags)
  actionStatus = "Comprobando el estado original y activando el reemplazo…"
  controller.activate(source:source,lease:lease) { [weak self] ok,message in
   guard let self else { return }
   guard ok,!self.isRestoring else { self.actionStatus = message;return }
   self.mappings.removeAll{$0.source == source || $0.source == nativeSource}
   self.mappings.append(Mapping(source:source,action:action,keyCode:keyCode,modifiers:modifiers,application:application,audioOutputUID:audioOutputUID));self.persist()
   self.lastSource = source;self.learning = false;self.enabled = true
   self.actionStatus = "Reemplazo activado y estado de desvío verificado. Comprueba el resultado con la tecla."
  }
 }
 func executeExclusive(_ source:String) {
  guard capturing,enabled,!isRestoring,let registration = receiverRegistrations.first(where:{$0.diversionController?.isActive(source:source) == true}),let lease = registration.diversionController?.activeSources()[source],verifiedIdentities[lease.endpoint + "|slot=\(lease.slot)"]?.wirelessID == lease.wirelessID,let mapping = mappings.first(where:{$0.source == source && $0.isEnabled}) else { return }
  if learning {
   let key = lease.endpoint + "|slot=\(lease.slot)";lastSource = source;learnedEndpoint = key;selected = key;lastEvent = mapping.controlLabel
   return
  }
  perform(mapping)
 }
 func restoreSelectedOriginal() {
  guard let mapping = selectedMapping else { actionStatus = "Este control no tiene ninguna asignación de Korda."; return }
  remove(mapping)
 }
 func isExclusiveMappingActive(_ mapping:Mapping) -> Bool { receiverRegistrations.contains{$0.diversionController?.isActive(source:mapping.source) == true} }
 private func restoreMapping(_ mapping:Mapping,completion:@escaping(Bool)->Void) {
  guard let controller = receiverRegistrations.compactMap(\.diversionController).first(where:{$0.requiresRestoration(source:mapping.source)}) else { completion(true);return }
  controller.restore(source:mapping.source) { [weak self] ok,message in self?.actionStatus = message;completion(ok) }
 }
 func toggleMapping(_ mapping: Mapping, enabled: Bool) {
  if mapping.source.hasPrefix("keyboard|"),enabled,isExclusiveMappingActive(mapping),let index = mappings.firstIndex(where:{$0.id == mapping.id}) { mappings[index].isEnabled = true;persist();return }
  if mapping.source.hasPrefix("keyboard|"),enabled,!isExclusiveMappingActive(mapping) {
   activateSavedExclusive(mapping) { [weak self] ok in
    guard let self,ok,let index = self.mappings.firstIndex(where:{$0.id == mapping.id}) else { return };self.mappings[index].isEnabled = true;self.persist()
   };return
  }
  restoreMapping(mapping) { [weak self] ok in
   guard let self,ok,let index = self.mappings.firstIndex(where:{$0.id == mapping.id}) else { return };self.mappings[index].isEnabled = enabled;self.persist()
  }
 }
 func remove(_ mapping: Mapping) {
  restoreMapping(mapping) { [weak self] ok in
   guard let self,ok else { return };self.mappings.removeAll{$0.id == mapping.id};self.persist();self.actionStatus = "Asignación eliminada. Korda no aplica esta acción."
  }
 }
 private func catalogMatch(_ mapping:Mapping) -> (KeyboardFeatureCatalog,KeyboardControlInfo,ReceiverReportRegistration)? {
  for catalog in keyboardCatalogs.values {
   guard verifiedIdentities[catalog.endpoint + "|slot=\(catalog.slot)"]?.wirelessID == catalog.wirelessID else { continue }
   for control in catalog.controls {
    guard let usage = control.consumerUsage,catalog.control(forUsage:usage)?.cid == control.cid,exclusiveSource(catalog,control:control,usage:usage) == mapping.source else { continue }
    if let registration = receiverRegistrations.first(where:{identity($0.device) == catalog.endpoint}) { return (catalog,control,registration) }
   }
  }
  return nil
 }
 private func activateSavedExclusive(_ mapping:Mapping,completion:@escaping(Bool)->Void) {
  guard enabled,!isRestoring,let (catalog,control,registration) = catalogMatch(mapping),!registration.identityBusy,!registration.featureBusy,registration.pendingManagement == nil,let controller = registration.diversionController else { actionStatus = "Reanuda Korda y consulta la compatibilidad del teclado para aplicar este reemplazo.";completion(false);return }
  let lease = KeyboardDiversionLease(endpoint:catalog.endpoint,slot:catalog.slot,wirelessID:catalog.wirelessID,featureIndex:catalog.featureIndex,cid:control.cid,capabilityFlags:control.flags)
  controller.activate(source:mapping.source,lease:lease) { [weak self] ok,message in self?.actionStatus = message;completion(ok) }
 }
 private func resumeExclusiveMappingsIfPossible() {
  guard enabled,capturing,!isRestoring else { return }
  let saved = mappings.filter{$0.isEnabled && $0.source.hasPrefix("keyboard|")}
  guard !saved.isEmpty else { return }
  for target in verifiedIdentities.values where target.kind == 1 {
   let prefix = "keyboard|endpoint=\(target.endpoint)|slot=\(target.slot)|wpid=\(String(format:"%04X",target.wirelessID))|"
   guard saved.contains(where:{$0.source.hasPrefix(prefix)}),let registration = receiverRegistrations.first(where:{identity($0.device) == target.endpoint}),!registration.identityBusy,!registration.featureBusy,registration.pendingManagement == nil,registration.diversionController?.busy != true else { continue }
   if keyboardCatalogs[target.key] == nil {
    if exclusiveDiscoveryAttempted.insert(target.key).inserted { registration.discoverKeyboard(target) }
   } else if let rule = saved.first(where:{$0.source.hasPrefix(prefix) && !exclusiveActivationAttempted.contains($0.source) && registration.diversionController?.isActive(source:$0.source) != true}) {
    exclusiveActivationAttempted.insert(rule.source)
    activateSavedExclusive(rule) { [weak self] _ in self?.resumeExclusiveMappingsIfPossible() }
   }
  }
 }
 func persist() { if let data = try? JSONEncoder().encode(mappings) { UserDefaults.standard.set(data, forKey: "mappings") } }
 func testAction(action: String, keyCode: UInt16, modifiers: UInt64, application:ApplicationTarget? = nil,audioOutputUID:String? = nil) {
  perform(Mapping(source:"manual-test",action:action,keyCode:keyCode,modifiers:modifiers,application:application,audioOutputUID:audioOutputUID))
 }
 @discardableResult func perform(_ mapping: Mapping) -> Bool {
  if mapping.isDigitalVolumeAction {
   guard let uid = mapping.audioOutputUID,audio.isProcessing,audio.activeOutputUID == uid else { actionStatus = "Activa primero el control digital de la salida elegida en Dispositivos o Ajustes → Sonido."; return false }
   switch mapping.action {
   case "digitalVolumeUp":audio.adjust(step:1.0/16)
   case "digitalVolumeDown":audio.adjust(step:-1.0/16)
   default:audio.toggleMute()
   }
   actionStatus = audio.isMuted ? "Salida silenciada por Korda." : "Volumen Korda: " + String(Int(audio.level * 100)) + "%"
   return true
  }
  if mapping.action == "launchApplication" {
   guard let target = mapping.application else { actionStatus = "Elige una aplicación para esta asignación."; return false }
   var candidates: [URL] = []
   if let bookmark = target.bookmark {
    var stale = false
    if let url = try? URL(resolvingBookmarkData:bookmark,options:[.withoutUI,.withoutMounting],relativeTo:nil,bookmarkDataIsStale:&stale) { candidates.append(url) }
   }
   candidates.append(URL(fileURLWithPath:target.path))
   if let identifier = target.bundleIdentifier,let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:identifier) { candidates.append(url) }
   guard let url = candidates.first(where:{ candidate in
    guard candidate.isFileURL,let values = try? candidate.resourceValues(forKeys:[.isApplicationKey]),values.isApplication == true,let bundle = Bundle(url:candidate) else { return false }
    return target.bundleIdentifier == nil || bundle.bundleIdentifier == target.bundleIdentifier
   }) else { actionStatus = "No se encuentra " + target.name + ". Vuelve a elegir la aplicación."; return false }
   NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration()) { [weak self] app,error in
    DispatchQueue.main.async {
     self?.actionStatus = error.map { "No se pudo abrir " + target.name + ": " + $0.localizedDescription } ?? (app == nil ? "macOS no confirmó la apertura." : target.name + " abierta.")
    }
   }
   actionStatus = "Abriendo " + target.name + "…"; return true
  }
  guard AXIsProcessTrusted() else { actionStatus = "La emisión requiere Accesibilidad para esta aplicación"; return false }
  if mapping.action == "launchCalculator" {
   guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.calculator") else { actionStatus = "Calculadora no disponible"; return false }
   NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration())
   actionStatus = "Calculadora solicitada"; return true
  }
  var events: [CGEvent] = []
  if mapping.action == "shortcut" {
   guard mapping.keyCode <= 127 else { actionStatus = "Código de tecla no válido"; return false }
   for down in [true,false] {
    guard let event = CGEvent(keyboardEventSource:nil,virtualKey:mapping.keyCode,keyDown:down) else { actionStatus = "No se pudo crear el evento"; return false }
    event.flags = CGEventFlags(rawValue:mapping.modifiers); events.append(event)
   }
  } else {
   let codes = ["volumeUp":0,"volumeDown":1,"mute":7,"playPause":16,"next":17,"previous":18]
   guard let code = codes[mapping.action] else { actionStatus = "Acción desconocida"; return false }
   for down in [true,false] {
    guard let event = NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:NSEvent.ModifierFlags(rawValue:down ? 0xa00 : 0xb00),timestamp:0,windowNumber:0,context:nil,subtype:8,data1:(code << 16) | ((down ? 0xa : 0xb) << 8),data2:-1)?.cgEvent else { actionStatus = "No se pudo crear el evento multimedia"; return false }
    events.append(event)
   }
  }
  for event in events { event.post(tap:.cghidEventTap) }
  actionStatus = "Acción enviada: \(mapping.action). Verifica el resultado en macOS."
  return true
 }

}
private enum ReceiverManagementPrompt: Identifiable {
 case pair(String)
 case unpair(HIDDeviceIdentity)
 var id:String { switch self { case .pair(let endpoint): return "pair:" + endpoint; case .unpair(let target): return "unpair:" + target.key } }
}
struct MainView: View {
 @ObservedObject var store: DeviceStore
 @State private var page = "devices"
 @State private var settingsPage = "general"
 @State private var search = ""
 @State private var showInfrastructure = false
 @State private var loginEnabled = SMAppService.mainApp.status == .enabled
 @State private var loginError = ""
 @State private var action = "original"
 @State private var application: ApplicationTarget?
 @State private var applicationError = ""
 @State private var audioOutputUID = ""
 private var isDigitalAction:Bool { ["digitalVolumeUp","digitalVolumeDown","digitalMute"].contains(action) }
 @State private var keyCode = "0"
 @State private var namedKey = "left"
 @State private var advancedKey = false
 @State private var replaceOriginal = false
 @State private var managementPrompt: ReceiverManagementPrompt?
 private var chosenKeyCode: UInt16? { advancedKey ? UInt16(keyCode) : NamedShortcutKey.all.first(where:{$0.id == namedKey})?.keyCode }
 private var chosenModifiers: UInt64 {
  var flags = CGEventFlags()
  if command { flags.insert(.maskCommand) }; if shift { flags.insert(.maskShift) }; if option { flags.insert(.maskAlternate) }; if control { flags.insert(.maskControl) }
  return flags.rawValue
 }
 @State private var command = true
 @State private var shift = false
 @State private var option = false
 @State private var control = false
 private func chooseApplication() {
  let panel = NSOpenPanel()
  panel.title = "Elige la aplicación que abrirá este control"
  panel.prompt = "Elegir aplicación"
  panel.canChooseFiles = true;panel.canChooseDirectories = false
  panel.allowsMultipleSelection = false;panel.treatsFilePackagesAsDirectories = false
  panel.directoryURL = URL(fileURLWithPath:"/Applications",isDirectory:true)
  panel.allowedContentTypes = [.applicationBundle]
  panel.begin { response in
   guard response == .OK,let url = panel.url else { return }
   guard let values = try? url.resourceValues(forKeys:[.isApplicationKey,.localizedNameKey]),values.isApplication == true,let bundle = Bundle(url:url) else { applicationError = "Selecciona una aplicación de macOS.";return }
   application = ApplicationTarget(name:values.localizedName ?? url.deletingPathExtension().lastPathComponent,path:url.path,bundleIdentifier:bundle.bundleIdentifier,bookmark:try? url.bookmarkData(options:[],includingResourceValuesForKeys:nil,relativeTo:nil))
   applicationError = ""
  }
 }
 @ViewBuilder private func identifiedControls(_ device:DeviceInfo,_ identity:HIDDeviceIdentity) -> some View {

       if identity.kind == 1 && store.keyboardRouteIsUnique(identity) {
        Text("Controles comunes · comprueba que existan en tu teclado").font(.headline)
        LazyVGrid(columns:[GridItem(.adaptive(minimum:150))],spacing:10) {
        ForEach([UInt32(233),234,226,205,182,181,402],id: \.self) { usage in
         let source = store.transportID(for:device.id) + ":12:\(usage)"
         Button {
          store.chooseControl(source)
          replaceOriginal = store.canReplaceSelectedControl
          action = "original"
          if let mapping = store.selectedMapping {
           audioOutputUID = mapping.audioOutputUID ?? "";application = mapping.application;action = mapping.action; keyCode = String(mapping.keyCode); advancedKey = true
           command = mapping.modifiers & 1048576 != 0; shift = mapping.modifiers & 131072 != 0
           option = mapping.modifiers & 524288 != 0; control = mapping.modifiers & 262144 != 0
          }
         } label: { Label(CapturePolicy.label(page:12,usage:usage),systemImage:controlIcon(usage)).frame(maxWidth:.infinity,minHeight:44) }.buttonStyle(.bordered)
        }
        }
       } else if identity.kind == 1 {
        Text("Varios teclados comparten este receptor. La interfaz estándar no permite distinguir sus teclas; no se ofrecen asignaciones individuales por esta ruta.").font(.caption)
       } else if identity.wirelessID == 0x1028 {
        ForEach([UInt8(4),5],id: \.self) { button in
         Button(button == 4 ? "Atrás" : "Adelante") {
          let profile = ReceiverMappingProfile(endpoint:identity.endpoint,slot:identity.slot,route:.synthetic1B04)
          store.chooseControl(profile.source(button:button))
          replaceOriginal = false;action = "original"
          if let mapping = store.mappings.first(where:{$0.source == store.lastSource}) {
           audioOutputUID = mapping.audioOutputUID ?? "";application = mapping.application;action = mapping.action; keyCode = String(mapping.keyCode); advancedKey = true
           command = mapping.modifiers & 1048576 != 0; shift = mapping.modifiers & 131072 != 0
           option = mapping.modifiers & 524288 != 0; control = mapping.modifiers & 262144 != 0
          }
         }
        }
       }
 }
 @ViewBuilder private var savedMappingRows: some View {
  if store.mappings.isEmpty { Text("Aún no hay asignaciones. Elige un dispositivo y selecciona su primer control.").foregroundStyle(.secondary) }
  ForEach(store.mappings) { mapping in mappingRow(mapping) }
 }
 @ViewBuilder private func mappingRow(_ mapping:Mapping) -> some View {
  HStack(spacing:12) {
   Toggle("Activa",isOn:Binding(get:{store.mappings.first(where:{$0.id == mapping.id})?.isEnabled ?? false},set:{store.toggleMapping(mapping,enabled:$0)})).labelsHidden().accessibilityLabel("Activar " + mapping.controlLabel)
   VStack(alignment:.leading,spacing:4) {
    Text(store.deviceLabel(for:mapping.source) + " · " + mapping.controlLabel).font(.headline)
    Text(mapping.actionLabel).foregroundStyle(.secondary)
    if mapping.source.hasPrefix("keyboard|") {
     Text(store.isExclusiveMappingActive(mapping) ? "Reemplazo activo · desvío verificado" : "Reemplazo guardado · sin activar").font(.caption).foregroundStyle(.secondary)
    }
   }
   Spacer()
   if mapping.source.hasPrefix("keyboard|"),mapping.isEnabled,!store.isExclusiveMappingActive(mapping) {
    Button("Aplicar") { store.toggleMapping(mapping,enabled:true) }.disabled(store.isRestoring)
   }
   Button("Editar") {
    guard store.editMapping(mapping) else { return };page = "devices";replaceOriginal = mapping.source.hasPrefix("keyboard|")
    audioOutputUID = mapping.audioOutputUID ?? "";application = mapping.application;action = mapping.action;keyCode = String(mapping.keyCode);advancedKey = true
    command = mapping.modifiers & 1048576 != 0;shift = mapping.modifiers & 131072 != 0
    option = mapping.modifiers & 524288 != 0;control = mapping.modifiers & 262144 != 0
   }
   Button("Eliminar") { store.remove(mapping) }.disabled(store.isRestoring)
  }.padding(12).background(.quaternary.opacity(0.2),in:RoundedRectangle(cornerRadius:12))
 }
 @ViewBuilder private var receiverManagementPanel: some View {
  GroupBox("Receptores y emparejamiento") {
   VStack(alignment:.leading,spacing:12) {
    Text("Añade dispositivos compatibles con Unifying al receptor elegido. Quitar un dispositivo borra su vínculo: dejará de controlar este Mac hasta volver a emparejarlo. Cierra otras aplicaciones de emparejamiento durante esta operación.").font(.caption)
    Button("Preparar receptores / actualizar dispositivos") { store.prepareReceiverManagement() }
    ForEach(store.receiverEndpoints,id:\.self) { endpoint in
     VStack(alignment:.leading,spacing:8) {
      Text(store.receiverName(endpoint)).font(.headline)
      DisclosureGroup("Identificación del receptor") { Text(endpoint).font(.caption.monospaced()).textSelection(.enabled) }
      HStack {
       Button("Añadir / emparejar dispositivo…") { managementPrompt = .pair(endpoint) }.disabled(!store.canManageReceiver(endpoint) || store.pairingDeadlines[endpoint] != nil)
       Button("Cerrar emparejamiento") { store.manageReceiver(endpoint,command:.closePairing) }.disabled(!store.canManageReceiver(endpoint))
      }
      if let deadline = store.pairingDeadlines[endpoint] { Text("Plazo de emparejamiento hasta \(deadline.formatted(date:.omitted,time:.shortened)). Apaga y enciende sólo el dispositivo que quieres añadir.").font(.caption) }
      ForEach(store.pairedDevices(endpoint),id:\.key) { target in
       HStack {
        Text("\(target.displayName) · posición \(target.slot) · HID++ \(String(format:"%04X",target.wirelessID))")
        Spacer()
        Button("Quitar…") { managementPrompt = .unpair(target) }.disabled(!store.canManageReceiver(endpoint) || store.pairingDeadlines[endpoint] != nil)
       }
      }
      Text(store.managementStatus[endpoint] ?? "Consulta los dispositivos antes de iniciar una operación. Sólo receptores Unifying compatibles; no Bluetooth ni Bolt.").font(.caption).textSelection(.enabled)
     }.padding(.vertical,8)
     Divider()
    }
   }.frame(maxWidth:.infinity,alignment:.leading)
  }
 }
 @ViewBuilder private var keyboardDiscoveryPanel: some View {
  GroupBox("Sustitución de teclas multimedia · compatibilidad") {
   VStack(alignment:.leading,spacing:10) {
    Text("Esta consulta sólo lee capacidades. Los reemplazos se activan desde Dispositivos para controles compatibles; Korda verifica el desvío y restaura el estado previo al pausar o salir.").font(.caption)
    ForEach(store.verifiedIdentities.values.filter{$0.kind == 1}.sorted{$0.key < $1.key},id:\.key) { target in
     VStack(alignment:.leading,spacing:6) {
      HStack {
       Text(target.displayName).font(.headline)
       Button("Consultar capacidad de sustitución") { store.discoverKeyboard(target) }.disabled(!store.canManageReceiver(target.endpoint) || store.pairingDeadlines[target.endpoint] != nil)
      }
      Text(store.keyboardDiscoveryStatus[target.key] ?? "Pendiente de consultar con el teclado encendido.").font(.caption).textSelection(.enabled)
      if let trace = store.keyboardDiscoveryTrace[target.key], !trace.isEmpty {
       DisclosureGroup("Detalle de la consulta") {
        ForEach(Array(trace.enumerated()),id:\.offset) { entry in Text(entry.element).font(.caption.monospaced()).textSelection(.enabled) }
       }
      }
      if let controls = store.keyboardControls[target.key], !controls.isEmpty {
       DisclosureGroup("Controles declarados por el teclado") {
        ForEach(Array(controls.enumerated()),id:\.offset) { entry in
         Text(String(format:"CID %04X · tarea %04X · flags %04X · %@",entry.element.cid,entry.element.task,entry.element.flags,entry.element.isDivertable ? "declara desvío" : "sin desvío declarado")).font(.caption.monospaced()).textSelection(.enabled)
        }
       }
      }
     }
    }
   }.frame(maxWidth:.infinity,alignment:.leading)
  }
 }
 private func controlIcon(_ usage:UInt32)->String {
  switch usage { case 233:return "speaker.wave.3";case 234:return "speaker.wave.1";case 226:return "speaker.slash";case 205:return "playpause";case 181:return "forward.end";case 182:return "backward.end";default:return "calculator" }
 }
 private var visibleDevices:[DeviceInfo] { store.sidebarDevices.filter { device in
  (search.isEmpty || device.name.localizedCaseInsensitiveContains(search)) && (showInfrastructure || (!device.detail.contains("Hub") && !device.name.contains("Host Controller")))
 } }
 private func deviceIcon(_ device:DeviceInfo)->String {
  if device.id.hasPrefix("audio|") { return "speaker.wave.2" }
  if device.detail.contains("Teclado") { return "keyboard" }
  if device.detail.contains("Ratón") || device.name.contains("M570") { return "computermouse" }
  if device.detail.contains("vídeo") || device.detail.contains("Cámara") { return "web.camera" }
  if device.detail.contains("Almacenamiento") { return "externaldrive" }
  return "cable.connector"
 }
 @ViewBuilder private var deviceContent:some View {
     Text("1. Elige un dispositivo · 2. Selecciona un control · 3. Guarda su acción").foregroundStyle(.secondary)
     if let device = store.sidebarDevices.first(where: { $0.id == store.selected }) {
      Text(device.name).font(.title2)
      Text(device.detail).textSelection(.enabled)
      if let usb = device.usb {
       DisclosureGroup("Información del dispositivo") {
        VStack(alignment:.leading,spacing:6) {
         Text("Nombre informado: \(usb.name)").font(.caption).textSelection(.enabled)
         ForEach(usb.details,id:\.self) { Text($0).font(.caption).textSelection(.enabled) }
         if device.device != nil { Text("Controles HID: puedes aprender botones adicionales, teclas multimedia y F1–F24. El reemplazo exclusivo de la función original sigue pendiente.").font(.caption) }
         else { Text("Este dispositivo está incluido en el inventario. Korda todavía no ofrece ajustes directos para esta clase; eso no significa que el hardware carezca de ellos.").font(.caption) }
         if usb.vendorID == 1133 && usb.productID == 50475 { Text("Las entradas estándar del receptor no identifican por sí solas al periférico que las envía. Administra cada dispositivo identificado en su propia entrada.").font(.caption) }
         if usb.usbClass == 1 || usb.interfaceClasses.contains(1) {
          Button("Abrir ajustes de sonido de macOS") { if let url = URL(string:"x-apple.systempreferences:com.apple.preference.sound") { NSWorkspace.shared.open(url) } }
         }
        }.frame(maxWidth:.infinity,alignment:.leading)
       }
      }
      if device.id.hasPrefix("audio|") { DigitalAudioPanel(controller:store.audio,outputUID:String(device.id.dropFirst(6))) }
      if let identity = store.verifiedIdentities[device.id] { identifiedControls(device,identity) }
      if device.device != nil {
       Button("Detectar otro control") { if !store.capturing { store.resumeBackground() }; store.learning = true }
       if store.learning { Text("Pulsa una vez el control que quieres configurar.").font(.callout).foregroundStyle(.secondary) }
       if !store.lastSource.isEmpty { Label(store.lastEvent,systemImage:"cursorarrow.click").font(.headline) }
       Text(store.actionStatus).font(.callout).textSelection(.enabled)
       Picker("Acción", selection: $action) {
        Text("Función original (sin asignación de Korda)").tag("original")
        Text("Subir volumen").tag("volumeUp"); Text("Bajar volumen").tag("volumeDown"); Text("Silenciar").tag("mute"); Text("Reproducir / pausa").tag("playPause"); Text("Pista siguiente").tag("next"); Text("Pista anterior").tag("previous"); Text("Abrir aplicación…").tag("launchApplication"); Text("Abrir Calculadora").tag("launchCalculator"); Text("Atajo de teclado").tag("shortcut"); Text("Subir volumen · Korda (salida digital)").tag("digitalVolumeUp"); Text("Bajar volumen · Korda (salida digital)").tag("digitalVolumeDown"); Text("Silenciar · Korda (salida digital)").tag("digitalMute")
       }
       if action != "original" {
        Toggle("Reemplazar la función original (en pruebas)",isOn:$replaceOriginal).disabled(!store.canReplaceSelectedControl)
        Text(replaceOriginal ? "Se restaurará el estado anterior al pausar o salir. La activación requiere verificar el desvío." : "Acción adicional: la función original también se ejecutará.").font(.caption).foregroundStyle(.secondary)
        if replaceOriginal { Text("La recuperación tras forzar el cierre o una caída todavía está pendiente. Durante la prueba usa Pausar o Salir de Korda.").font(.caption).foregroundStyle(.secondary) }
        if !store.canReplaceSelectedControl { Text("El reemplazo necesita un control compatible y una consulta reciente del teclado.").font(.caption).foregroundStyle(.secondary) }
       }
       if isDigitalAction {
        Picker("Salida de audio",selection:$audioOutputUID) {
         Text("Selecciona una salida").tag("")
         ForEach(store.audio.outputs) { output in Text(output.name).tag(output.id) }
         if !audioOutputUID.isEmpty && !store.audio.outputs.contains(where:{$0.id == audioOutputUID}) { Text("Salida desconectada").tag(audioOutputUID) }
        }
        Text("Activa el control de esa salida en Dispositivos o Ajustes → Sonido. Esta acción ajusta el audio con Korda; no envía la tecla de volumen de macOS.").font(.caption).foregroundStyle(.secondary)
       }
       if action == "launchApplication" {
        HStack {
         Image(systemName:"app")
         Text(application?.name ?? "Ninguna aplicación seleccionada").lineLimit(1)
         Spacer()
         Button(application == nil ? "Elegir aplicación…" : "Cambiar…") { chooseApplication() }
        }
        if !applicationError.isEmpty { Text(applicationError).font(.caption).foregroundStyle(.red) }
        Text("Abre la aplicación elegida o la trae al frente si ya está abierta.").font(.caption).foregroundStyle(.secondary)
       }
       if action == "shortcut" {
        Picker("Tecla",selection:$namedKey) { ForEach(NamedShortcutKey.all) { key in Text(key.label).tag(key.id) } }.disabled(advancedKey)
        DisclosureGroup("Atajo avanzado") {
         Toggle("Usar código virtual",isOn:$advancedKey)
         if advancedKey { TextField("Código virtual macOS (0–127)",text:$keyCode) }
        }
        HStack { Toggle("⌘", isOn: $command); Toggle("⇧", isOn: $shift); Toggle("⌥", isOn: $option); Toggle("⌃", isOn: $control) }
       }
       Button("Guardar asignación") {
        if replaceOriginal { store.saveExclusive(action:action,keyCode:chosenKeyCode ?? 0,modifiers:chosenModifiers,application:application,audioOutputUID:audioOutputUID.isEmpty ? nil : audioOutputUID) }
        else { store.save(action:action,keyCode:chosenKeyCode ?? 0,modifiers:chosenModifiers,application:application,audioOutputUID:audioOutputUID.isEmpty ? nil : audioOutputUID) }
       }.disabled((isDigitalAction && audioOutputUID.isEmpty) || (action == "launchApplication" && application == nil) || store.isRestoring || store.lastSource.isEmpty || (action != "original" && replaceOriginal && !store.canReplaceSelectedControl) || (action == "shortcut" && (chosenKeyCode.map { $0 > 127 } ?? true)))
       Button("Probar acción seleccionada") {
        store.testAction(action:action,keyCode:chosenKeyCode ?? 0,modifiers:chosenModifiers,application:application,audioOutputUID:audioOutputUID.isEmpty ? nil : audioOutputUID)
       }.disabled((isDigitalAction && (audioOutputUID.isEmpty || store.audio.activeOutputUID != audioOutputUID)) || (action == "launchApplication" && application == nil) || action == "original" || (!isDigitalAction && action != "launchApplication" && !AXIsProcessTrusted()) || (action == "shortcut" && (chosenKeyCode.map { $0 > 127 } ?? true)))
      }

     } else { Text("Selecciona un dispositivo para inspeccionar sus controles.") }
 }
 @ViewBuilder private var settingsContent:some View {
  Picker("Ajustes",selection:$settingsPage) { Text("General").tag("general"); Text("Permisos").tag("permissions"); Text("Sonido").tag("audio"); Text("Diagnósticos").tag("diagnostics") }.pickerStyle(.segmented)
  if settingsPage == "audio" { DigitalAudioPanel(controller:store.audio) }
  if settingsPage == "general" {
   GroupBox("Funcionamiento") { VStack(alignment:.leading,spacing:12) {
    Text("Cerrar la ventana mantiene Korda en la barra de menús. Pausar restaura las teclas reemplazadas antes de detener las asignaciones.")
    Toggle("Iniciar con macOS",isOn:Binding(get:{loginEnabled},set:{ enabled in
     do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled }
     catch { loginError = error.localizedDescription }
    }))
    Text(loginError).font(.caption)
   }.padding(8) }
   receiverManagementPanel
  }
  if settingsPage == "permissions" {
     GroupBox("Permisos de Korda") {
      VStack(alignment:.leading,spacing:8) {
       Text("Monitorización de entrada permite recibir botones. Accesibilidad permite ejecutar tus acciones. Korda no registra el texto que escribes.").font(.caption)
       HStack {
        Button("Solicitar monitorización") { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent); store.refresh() }
        Button("Solicitar Accesibilidad") {
         _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
         store.refresh()
        }
        Button("Actualizar estado") { store.refresh() }
       }
       HStack {
        Button("Abrir Monitorización de entrada") { if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) } }
        Button("Abrir Accesibilidad") { if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) } }
       }
      }.frame(maxWidth:.infinity,alignment:.leading)
     }
 }
  if settingsPage == "diagnostics" {
       HStack {
        Button(store.capturing ? "Detener captura y asignaciones" : "Iniciar captura de botones") { store.capturing ? store.stop() : store.start() }
        Toggle("Ejecutar asignaciones", isOn: $store.enabled).disabled(!store.capturing || store.hasExclusiveObligations)
        if store.hasExclusiveObligations { Text("Usa Pausar para restaurar las teclas antes de detener los reemplazos.").font(.caption) }
       }
       Toggle("Aprender pulsaciones (desactivar para fijar el botón)", isOn: $store.learning).disabled(!store.capturing)
       Text(store.learning ? "Aprendizaje activo: pulsa el control que quieres asignar y desactiva el aprendizaje para conservarlo." : "Botón fijado: las nuevas pulsaciones no cambian la selección. La ejecución de asignaciones es independiente.").font(.caption)
       Text("Sólo se observan botones adicionales (3+), controles multimedia y F1–F24; no se registra texto. Las acciones originales no se bloquean: una asignación puede sumarse a la función existente.").font(.caption).foregroundStyle(.secondary)
       Text(store.lastEvent).font(.headline)
       DisclosureGroup("Últimas pulsaciones (máximo 10)") {
        ForEach(Array(store.recentEvents.enumerated()), id: \.offset) { entry in
         Text(entry.element).font(.caption.monospaced()).textSelection(.enabled)
        }
       }

   Text("Herramientas de soporte. No necesitas usarlas para administrar tus asignaciones.").foregroundStyle(.secondary)
   Text(store.status).font(.caption)
   keyboardDiscoveryPanel
     Divider()
     DisclosureGroup("Diagnóstico M570 · botones adicionales") {
      Toggle("Observar informe de ratón conocido (sólo diagnóstico)", isOn: $store.rawDiagnosticsEnabled).disabled(!store.capturing)
      Text("Detenido por defecto. Sólo interfaces Logitech de ratón con descriptor verificado, informe 2, botones 3–16. Ignora texto, movimiento y rueda; no guarda bytes ni crea asignaciones.").font(.caption)
      Text("Interfaces: \(store.rawInterfaceCount) · informes2: \(store.rawReportCount) · rechazados: \(store.rawRejectedCount) · transiciones extra: \(store.rawButtonCount) · pulsaciones HID estándar: \(store.standardButtonCount)").font(.caption.monospaced())
      ForEach(Array(store.rawEvents.enumerated()), id: \.offset) { entry in Text(entry.element).font(.caption.monospaced()).textSelection(.enabled) }
     }
     Divider()
     GroupBox("Identificación de dispositivos · HID++") {
      VStack(alignment:.leading,spacing:8) {
       Text("Consulta de lectura del receptor: identificador inalámbrico, tipo y nombre registrado. No cambia emparejamientos ni botones.").font(.caption)
       Button("Identificar dispositivos HID++") { store.identifyDevices() }
       Text(store.identificationStatus).font(.caption)
       ForEach(store.identificationErrors,id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
       ForEach(store.verifiedIdentities.keys.sorted(),id: \.self) { key in
        if let identity = store.verifiedIdentities[key] {
         Text(identity.label).font(.headline)
         Text(identity.endpoint + " · tipo \(identity.kind)").font(.caption.monospaced()).textSelection(.enabled)
        }
       }
      }.frame(maxWidth:.infinity,alignment:.leading)
     }
     DisclosureGroup("Diagnóstico pasivo del receptor · DJ / HID++") {
      Toggle("Observar colección de fabricante verificada", isOn: $store.receiverDiagnosticsEnabled).disabled(!store.capturing)
      Text("Escucha sin apertura exclusiva; identificación mediante consultas de lectura explícitas. Sólo cuenta ID/longitud de informes desconocidos; interpreta ratón DJ20 y candidatos 1B04 estrictos, por interfaz y slot. No registra teclado, coordenadas ni bytes crudos. Sólo las rutas autorizadas abajo permiten aprender y ejecutar asignaciones.").font(.caption)
      Text("Interfaces admitidas: \(store.receiverInterfaceCount) · ignorados: \(store.receiverIgnoredCount)").font(.caption.monospaced())
      ForEach(store.receiverProfiles) { profile in
       VStack(alignment:.leading) {
        Text("\(profile.endpoint) · slot \(profile.slot) · \(profile.route.label)").font(.caption.monospaced())
        Text("Perfil ligado al receptor y slot, no a una identidad permanente. Un nuevo emparejamiento puede reutilizar este slot.").font(.caption)
        if profile.route == .synthetic1B04 {
         Toggle("Según mi prueba: botón 4 Atrás y botón 5 Adelante",isOn:Binding(get:{store.receiverProfiles.first(where:{$0.id == profile.id})?.buttonLabelsConfirmed ?? false},set:{store.confirmReceiverButtonLabels(profile,confirmed:$0)})).disabled(!profile.enrolled)
        }
        Toggle("Usar esta ruta para asignaciones",isOn:Binding(get:{store.receiverProfiles.first(where:{$0.id == profile.id})?.enrolled ?? false},set:{store.enrollReceiverProfile(profile,enabled:$0)}))
       }
      }
      ForEach(store.receiverOpenResults,id: \.self) { Text($0).font(.caption.monospaced()) }
      ForEach(store.receiverReportCounts.keys.sorted(),id: \.self) { key in Text("\(key): \(store.receiverReportCounts[key] ?? 0)").font(.caption.monospaced()) }
      ForEach(store.receiverAcceptedCounts.keys.sorted(),id: \.self) { key in Text("\(key): \(store.receiverAcceptedCounts[key] ?? 0)").font(.caption.monospaced()) }
      ForEach(store.observedM570Slots,id: \.self) { Text("M570 identificado por notificación: " + $0).font(.caption) }
      ForEach(Array(store.receiverEvents.enumerated()),id: \.offset) { entry in Text(entry.element).font(.caption.monospaced()).textSelection(.enabled) }
     }
 }
 }
 var body: some View {
  NavigationSplitView {
   TextField("Buscar dispositivo",text:$search).textFieldStyle(.roundedBorder).padding([.horizontal,.top])
   Toggle("Mostrar hubs e internos",isOn:$showInfrastructure).font(.caption).padding(.horizontal)
   List(visibleDevices, selection: $store.selected) { device in
    HStack { Image(systemName:deviceIcon(device)).frame(width:26).foregroundStyle(.mint); VStack(alignment: .leading) { Text(device.name).font(.headline); Text(device.detail).font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 7).tag(device.id)
   }.navigationTitle("Dispositivos")
   Button("Actualizar inventario") { store.refresh() }.padding()
  } detail: {
   ScrollView {
    VStack(alignment: .leading, spacing: 16) {
     HStack {
      Image(systemName:"keyboard").font(.largeTitle).foregroundStyle(.mint)
      Text("Korda").font(.largeTitle.bold())
      Spacer()
      Button(store.isRestoring ? "Restaurando…" : (store.hasBackgroundActivity ? "Pausar" : "Activar Korda")) { if store.hasBackgroundActivity { store.pauseBackground() } else { store.resumeBackground() } }.disabled(store.isRestoring)
     }
     Picker("Sección",selection:$page) {
      Text("Dispositivos").tag("devices"); Text("Asignaciones").tag("assignments"); Text("Ajustes").tag("settings")
     }.pickerStyle(.segmented)
     Label(store.capturing && store.enabled ? "Korda activa" : "Asignaciones pausadas",systemImage:store.capturing && store.enabled ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(.secondary)
     if store.isRestoring { ProgressView("Restaurando las teclas…") }
     if !store.exclusiveStatus.isEmpty { Text(store.exclusiveStatus).font(.caption).foregroundStyle(.secondary) }
     Text("\(store.usbDevices.count) entradas USB detectadas · incluye hubs y dispositivos internos").font(.caption)
     if let warning = store.usbInventoryWarning { Text(warning).font(.caption).foregroundStyle(.orange) }

     if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted || !AXIsProcessTrusted() {
      HStack { Label("Korda necesita permisos para controlar tus dispositivos",systemImage:"lock.shield"); Spacer(); Button("Revisar permisos") { page = "settings"; settingsPage = "permissions" } }.padding().background(.orange.opacity(0.1),in:RoundedRectangle(cornerRadius:12))
     }
     if page == "devices" { deviceContent }
     if page == "settings" { settingsContent }
     if page == "assignments" {
     Divider()
     Text("Asignaciones guardadas").font(.headline)
     Text(store.actionStatus).font(.caption).textSelection(.enabled)
     savedMappingRows
     Text("Las asignaciones se ejecutan mientras esta aplicación permanece abierta y la captura está activa. No instala controladores ni cambia permisos del sistema. Las teclas de texto y Fn no se remapean; las rutas propietarias requieren autorización explícita por receptor y slot.").font(.caption).foregroundStyle(.secondary)
     }
    }.padding(24)
   }
  }.frame(minWidth: 950, minHeight: 650)
   .onChange(of: store.selected) { _, selected in
    if selected != store.learnedEndpoint {
     store.lastSource = ""; store.lastEvent = "Sin eventos"
    }
    if let selected,let target = store.verifiedIdentities[selected],target.kind == 1,store.keyboardCatalogs[selected] == nil,store.canManageReceiver(target.endpoint) { store.discoverKeyboard(target) }
   }
   .alert(item:$managementPrompt) { prompt in
    switch prompt {
    case .pair(let endpoint):
     return Alert(title:Text("Emparejar con \(store.receiverName(endpoint))"),message:Text("Se abrirá una ventana de 60 segundos para vincular un dispositivo cercano compatible. Apaga y enciende sólo el que quieras añadir. Las asignaciones de este receptor se pausarán durante la operación."),primaryButton:.default(Text("Abrir emparejamiento")){ store.manageReceiver(endpoint,command:.openPairing) },secondaryButton:.cancel(Text("Cancelar")))
    case .unpair(let target):
     return Alert(title:Text("¿Quitar \(target.displayName)?"),message:Text("\(store.receiverName(target.endpoint)) · posición \(target.slot) · HID++ \(String(format:"%04X",target.wirelessID)). Dejará de controlar este Mac a través de este receptor. Necesitarás volver a emparejarlo para recuperarlo. Comprueba que tienes otro teclado o ratón disponible."),primaryButton:.destructive(Text("Quitar del receptor")){ store.manageReceiver(target.endpoint,command:.unpair(slot:target.slot),expectedWPID:target.wirelessID) },secondaryButton:.cancel(Text("Cancelar")))
    }
   }
 }
}
final class KordaAppDelegate: NSObject, NSApplicationDelegate {
 static weak var store:DeviceStore?
 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
 func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
  guard let store = Self.store else { return .terminateNow }
  store.stop { ok in DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate:ok) } }
  return .terminateLater
 }
}
struct KordaMenu: View {
 @ObservedObject var store: DeviceStore
 @Environment(\.openWindow) private var openWindow
 @State private var loginEnabled = SMAppService.mainApp.status == .enabled
 @State private var loginMessage = ""
 var body: some View {
  Text(store.capturing ? (store.enabled ? "Asignaciones activas" : "Captura activa · asignaciones pausadas") : "Captura y asignaciones pausadas")
  if store.audio.isProcessing { Text("Control digital de audio activo") }
  Button(store.hasBackgroundActivity ? "Pausar" : "Reanudar asignaciones") {
   if store.hasBackgroundActivity { store.pauseBackground() } else { store.resumeBackground() }
  }.disabled(store.isRestoring)
  Button("Abrir ajustes") { openWindow(id:"korda-settings"); NSApp.activate(ignoringOtherApps:true) }
  Divider()
  Toggle("Iniciar con macOS", isOn:Binding(get:{loginEnabled},set:{ desired in
   do {
    if desired { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    loginEnabled = SMAppService.mainApp.status == .enabled
    loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Pendiente de aprobación en Ítems de inicio" : ""
   } catch { loginEnabled = SMAppService.mainApp.status == .enabled; loginMessage = "No se pudo cambiar el inicio automático: \(error.localizedDescription)" }
  }))
  if !loginMessage.isEmpty { Text(loginMessage) }
  Divider()
  Button("Salir de Korda") { NSApp.terminate(nil) }.keyboardShortcut("q")
 }
}
@main struct KordaApp: App {
 @NSApplicationDelegateAdaptor(KordaAppDelegate.self) private var delegate
 @StateObject private var store: DeviceStore
 init() {
  let shared = DeviceStore()
  KordaAppDelegate.store = shared
  if UserDefaults.standard.bool(forKey:"backgroundAssignmentsEnabled") { shared.resumeBackground() }
  _store = StateObject(wrappedValue:shared)
 }
 var body: some Scene {
  Window("Korda",id:"korda-settings") { MainView(store:store) }
  MenuBarExtra("Korda",systemImage:"keyboard") { KordaMenu(store:store) }
 }
}
