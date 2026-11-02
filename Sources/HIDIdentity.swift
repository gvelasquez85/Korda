import Foundation
// Original read-only Unifying receiver-information requests. Protocol field
// references are documented in docs/hidpp-identification.md; no serial queries.
struct HIDIdentityReply { var wirelessID: UInt16?; var kind: UInt8?; var name: String? }
struct HIDIdentityQuery {
 enum Kind { case pairing, name }
 let slot: UInt8
 let kind: Kind
 var isValid: Bool { (1...6).contains(slot) }
 var selector: UInt8 { (kind == .pairing ? 0x20 : 0x40) + (isValid ? slot - 1 : 0) }
 var request: [UInt8] { isValid ? [0x10,0xff,0x83,0xb5,selector,0,0] : [] }
 func parse(_ bytes: [UInt8]) -> HIDIdentityReply? {
  guard isValid, bytes.count == 20, Array(bytes.prefix(5)) == [0x11,0xff,0x83,0xb5,selector] else { return nil }
  if kind == .pairing {
   let wpid = UInt16(bytes[7]) << 8 | UInt16(bytes[8])
   guard wpid != 0 && wpid != 0xffff else { return nil }
   return HIDIdentityReply(wirelessID:wpid,kind:bytes[11] & 15,name:nil)
  }
  let n = Int(bytes[5]); guard (1...14).contains(n) else { return nil }
  let chars = Array(bytes[6..<(6+n)])
  guard chars.allSatisfy({(32...126).contains($0)}), let name = String(bytes:chars,encoding:.ascii) else { return nil }
  return HIDIdentityReply(wirelessID:nil,kind:nil,name:name)
 }
}
struct HIDDeviceIdentity {
 let endpoint: String
 let slot: UInt8
 var wirelessID: UInt16
 var kind: UInt8
 var name: String?
 let checkedAt: Date
 var key: String { endpoint + "|slot=\(slot)" }
 var displayName: String {
  // Physical tests in acceptance.md associate these protocol names with the
  // owner's keyboards. Retain the protocol name in technical details.
  if wirelessID == 0x4076 { return "K540" }
  if wirelessID == 0x4024 { return "K400r" }
  if wirelessID == 0x1028 { return "M570" }
  if let name, !name.trimmingCharacters(in:.whitespaces).isEmpty { return name }
  return L10n.tr("{{0}} sin identificar", String(describing: categoryName))
 }
 var categoryName: String { kind == 1 ? L10n.tr("Teclado") : (kind == 2 ? L10n.tr("Ratón") : L10n.tr("Dispositivo")) }
 var label: String { L10n.tr("{{0}} · WPID {{1}} · posición {{2}}", String(describing: name ?? (wirelessID == 0x1028 ? L10n.tr("M570 (WPID del fabricante)") : L10n.tr("Dispositivo HID++"))), String(describing: String(format:"%04X",wirelessID)), String(describing: slot)) }
}
