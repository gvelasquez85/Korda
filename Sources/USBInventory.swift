import Foundation
import IOKit

struct USBDeviceInfo: Identifiable {
 let registryID: UInt64
 let name: String
 let vendorID: UInt32?
 let productID: UInt32?
 let locationID: UInt32?
 let manufacturer: String?
 let usbClass: UInt32?
 let speed: UInt32?
 var interfaceClasses: [UInt32] = []
 var id: String { "usb:\(registryID)" }
 var hidPrefix: String? {
  guard let vendorID, let productID, let locationID else { return nil }
  return "\(vendorID):\(productID):\(locationID)"
 }
 var category: String {
  if usbClass == 0 || usbClass == 239 {
   let classes = Set(interfaceClasses)
   if classes.contains(14) && classes.contains(1) { return "Cámara y audio USB" }
   if classes.contains(14) { return "Vídeo USB" }
   if classes.contains(1) { return "Audio USB" }
   if classes.contains(8) { return "Almacenamiento USB" }
   if classes.contains(3) { return "Dispositivo HID" }
   if classes.count > 1 { return "Dispositivo compuesto USB" }
  }
  switch usbClass { case 1: return "Audio USB"; case 3: return "Dispositivo HID"; case 8: return "Almacenamiento USB"; case 9: return "Hub USB"; case 14: return "Vídeo USB"; default: return "Dispositivo USB" }
 }
 var details: [String] {
  var rows = ["Tipo: \(category)"]
  if let manufacturer { rows.append("Fabricante: \(manufacturer)") }
  if let vendorID { rows.append(String(format:"Identificador de fabricante: %04X",vendorID)) }
  if let productID { rows.append(String(format:"Identificador de producto: %04X",productID)) }
  if let locationID { rows.append(String(format:"Ubicación USB: %08X",locationID)) }
  if let usbClass { rows.append("Clase USB: \(usbClass)") }
  if !interfaceClasses.isEmpty { rows.append("Clases de interfaz USB: " + interfaceClasses.map(String.init).joined(separator:", ")) }
  if let speed { rows.append("Código de velocidad USB declarado: \(speed)") }
  return rows
 }
 static func friendlyName(_ candidate: String?) -> String {
  let value = candidate?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
  return value.isEmpty ? "Dispositivo USB" : value
 }
}
struct USBInventorySnapshot {
 let devices: [USBDeviceInfo]
 let warning: String?
}
enum USBInventory {
 static func snapshot() -> USBInventorySnapshot {
  var found: [UInt64:USBDeviceInfo] = [:]
  var errors: [String] = []
  var transportKeys = Set<String>()
  for serviceClass in ["IOUSBHostDevice","IOUSBDevice"] {
   var iterator: io_iterator_t = 0
   let result = IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching(serviceClass),&iterator)
   guard result == KERN_SUCCESS else { errors.append("No se pudo consultar \(serviceClass) (\(result))."); continue }
   defer { IOObjectRelease(iterator) }
   while true {
    let service = IOIteratorNext(iterator)
    if service == 0 { break }
    defer { IOObjectRelease(service) }
    var registryID: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(service,&registryID) == KERN_SUCCESS else { continue }
    func property(_ key:String) -> Any? { IORegistryEntryCreateCFProperty(service,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() }
    func number(_ key:String) -> UInt32? { (property(key) as? NSNumber)?.uint32Value }
    func string(_ key:String) -> String? {
     guard let value = property(key) as? String else { return nil }
     let trimmed = value.trimmingCharacters(in:.whitespacesAndNewlines)
     return trimmed.isEmpty ? nil : trimmed
    }
    // Read selected public metadata only; no device open, serial or transfers.
    let name = USBDeviceInfo.friendlyName(string("USB Product Name") ?? string("kUSBProductString"))
    var interfaceClasses = Set<UInt32>()
    var children: io_iterator_t = 0
    if IORegistryEntryGetChildIterator(service,kIOServicePlane,&children) == KERN_SUCCESS {
     defer { IOObjectRelease(children) }
     while true {
      let child = IOIteratorNext(children); if child == 0 { break }
      defer { IOObjectRelease(child) }
      if IOObjectConformsTo(child,"IOUSBHostInterface") != 0 || IOObjectConformsTo(child,"IOUSBInterface") != 0,
         let value = IORegistryEntryCreateCFProperty(child,"bInterfaceClass" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber { interfaceClasses.insert(value.uint32Value) }
     }
    }
    var info = USBDeviceInfo(registryID:registryID,name:name,vendorID:number("idVendor"),productID:number("idProduct"),locationID:number("locationID"),manufacturer:string("USB Vendor Name"),usbClass:number("bDeviceClass"),speed:number("Device Speed"))
    info.interfaceClasses = interfaceClasses.sorted()
    if let key = info.hidPrefix {
     if !transportKeys.insert(key).inserted { continue }
    }
    found[registryID] = info
   }
  }
  return USBInventorySnapshot(devices:found.values.sorted { $0.name == $1.name ? $0.registryID < $1.registryID : $0.name < $1.name },warning:errors.isEmpty ? nil : errors.joined(separator:" "))
 }
}
