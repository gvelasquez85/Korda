import Foundation
@main struct USBInventoryTests {
 static func main() {
  let usb = USBDeviceInfo(registryID:123,name:"Receiver",vendorID:1133,productID:50475,locationID:123456,manufacturer:nil,usbClass:3,speed:nil)
  precondition(usb.hidPrefix == "1133:50475:123456")
  precondition(usb.id == "usb:123" && usb.category == "Dispositivo HID")
  precondition(USBDeviceInfo.friendlyName(" \n") == "Dispositivo USB")
  precondition(USBDeviceInfo.friendlyName(" Hub ") == "Hub")
  let missing = USBDeviceInfo(registryID:2,name:"Unknown",vendorID:nil,productID:nil,locationID:nil,manufacturer:nil,usbClass:nil,speed:nil)
  precondition(missing.hidPrefix == nil && missing.details == ["Tipo: Dispositivo USB"])
  precondition(!usb.details.joined().contains("serie"))
  var camera = USBDeviceInfo(registryID:3,name:"Camera",vendorID:1,productID:2,locationID:3,manufacturer:nil,usbClass:0,speed:nil)
  camera.interfaceClasses = [1,14]
  precondition(camera.category == "Cámara y audio USB")
  camera.interfaceClasses = [14]
  precondition(camera.category == "Vídeo USB")
  camera.interfaceClasses = [3]
  precondition(camera.category == "Dispositivo HID")
  if CommandLine.arguments.contains("--snapshot") {
   let inventory = USBInventory.snapshot()
   print("USB count: \(inventory.devices.count); warning: \(inventory.warning ?? "none")")
   for device in inventory.devices { print("\(device.name) | \(device.category) | \(device.id) | \(device.hidPrefix ?? "unknown")") }
  }
  print("PASS: USB labels, missing metadata and HID transport matching")
 }
}
