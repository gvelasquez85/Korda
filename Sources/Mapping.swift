import Foundation
struct CapturePolicy {
 static func allows(page: UInt32, usage: UInt32) -> Bool {
  guard usage > 0, usage < 65535 else { return false }
  return page == 12 || (page == 9 && usage >= 3) || (page == 7 && ((58...69).contains(usage) || (104...115).contains(usage)))
 }
 // Consumer usages from Apple's IOHIDUsageTables.h; names describe declarations, not tested behavior.
 static func label(page: UInt32, usage: UInt32) -> String {
  if page == 12, let name = [UInt32(233): "Subir volumen", 234: "Bajar volumen", 226: "Silenciar", 205: "Reproducir / pausa", 181: "Pista siguiente", 182: "Pista anterior", 402: "Calculadora", 545: "Buscar", 549: "Navegador: adelante", 548: "Navegador: atrás", 547: "Inicio del navegador"][usage] { return name }
  return "Página \(page) · botón \(usage)"
 }
}
struct ApplicationTarget: Codable, Equatable {
 let name: String
 let path: String
 let bundleIdentifier: String?
 let bookmark: Data?
}
struct Mapping: Codable, Equatable, Identifiable {
 var id: String { source }
 let source: String
 var action: String
 var keyCode: UInt16
 var modifiers: UInt64
 var isEnabled: Bool = true
 var application: ApplicationTarget?
 var audioOutputUID: String?
 init(source:String,action:String,keyCode:UInt16,modifiers:UInt64,isEnabled:Bool = true,application:ApplicationTarget? = nil,audioOutputUID:String? = nil) {
  self.source=source;self.action=action;self.keyCode=keyCode;self.modifiers=modifiers;self.isEnabled=isEnabled;self.application=application;self.audioOutputUID=audioOutputUID
 }
 private enum CodingKeys:String,CodingKey { case source,action,keyCode,modifiers,isEnabled,application,audioOutputUID }
 init(from decoder:Decoder) throws {
  let c = try decoder.container(keyedBy:CodingKeys.self)
  source = try c.decode(String.self,forKey:.source)
  action = try c.decode(String.self,forKey:.action)
  keyCode = try c.decode(UInt16.self,forKey:.keyCode)
  modifiers = try c.decode(UInt64.self,forKey:.modifiers)
  audioOutputUID = try c.decodeIfPresent(String.self,forKey:.audioOutputUID)
  application = try c.decodeIfPresent(ApplicationTarget.self,forKey:.application)
  isEnabled = try c.decodeIfPresent(Bool.self,forKey:.isEnabled) ?? true
 }
 var isDigitalVolumeAction:Bool { ["digitalVolumeUp","digitalVolumeDown","digitalMute"].contains(action) }
 var actionLabel: String {
  if isDigitalVolumeAction { return ["digitalVolumeUp":"Subir volumen · Korda","digitalVolumeDown":"Bajar volumen · Korda","digitalMute":"Silenciar · Korda"][action]! }
  if action == "launchApplication" { return "Abrir " + (application?.name ?? "aplicación sin seleccionar") }
  if action == "shortcut" {
   var prefix = ""
   if modifiers & 1048576 != 0 { prefix += "⌘" }
   if modifiers & 131072 != 0 { prefix += "⇧" }
   if modifiers & 524288 != 0 { prefix += "⌥" }
   if modifiers & 262144 != 0 { prefix += "⌃" }
   let punctuation: [UInt16:String] = [33:"[",30:"]"]
   let key = NamedShortcutKey.all.first(where:{$0.keyCode == keyCode})?.label ?? punctuation[keyCode] ?? "Tecla \(keyCode)"
   return prefix + key
  }
  return ["volumeUp":"Subir volumen","volumeDown":"Bajar volumen","mute":"Silenciar","playPause":"Reproducir / pausa","next":"Pista siguiente","previous":"Pista anterior","launchCalculator":"Abrir Calculadora"][action] ?? action
 }
 var controlLabel: String {
  if source.hasPrefix("keyboard|"),let tail = source.components(separatedBy:"|usage=").last,let usage = UInt32(tail) { return CapturePolicy.label(page:12,usage:usage) }
  if source.hasPrefix("receiver|"), let tail = source.components(separatedBy:"|button=").last, let button = UInt32(tail) {
   return button == 4 ? "Atrás (botón 4)" : button == 5 ? "Adelante (botón 5)" : "Botón \(button)"
  }
  let parts = source.split(separator:":")
  if parts.count >= 3, let page = UInt32(parts[parts.count-2]), let usage = UInt32(parts[parts.count-1]) { return CapturePolicy.label(page:page,usage:usage) }
  return "Control sin identificar"
 }
}

enum ReceiverMappingRoute: String, Codable {
 case djMouse, synthetic1B04
 var label: String { self == .djMouse ? "DJ20 ratón" : "candidato 1B04" }
}
struct ReceiverMappingProfile: Codable, Equatable, Identifiable {
 let endpoint: String
 let slot: UInt8
 let route: ReceiverMappingRoute
 var enrolled = false
 var buttonLabelsConfirmed = false
 var verifiedWirelessID: UInt16? = nil
 var id: String { "receiver|endpoint=\(endpoint)|slot=\(slot)|route=\(route.rawValue)" }
 func source(button: UInt8) -> String { id + "|button=\(button)" }
 func permitsIdentifiedDevice(_ current: UInt16?) -> Bool {
  guard enrolled, let expected = verifiedWirelessID, expected != 0, expected != 0xffff else { return false }
  return current == expected
 }
 // Labels require explicit user confirmation; pairing can reuse the receiver slot.
 func buttonLabel(_ button: UInt8) -> String {
  if enrolled && buttonLabelsConfirmed && route == .synthetic1B04 {
   if button == 4 { return "Atrás (botón 4, según prueba)" }
   if button == 5 { return "Adelante (botón 5, según prueba)" }
  }
  return "Botón \(button)"
 }
}
struct ReceiverMappingDecision {
 let source: String
 let learn: Bool
 let execute: Bool
}
struct ReceiverMappingRuntime {
 // Session switches are intentionally absent from persisted profiles/mappings.
 var executionEnabled = false
 var listening = false
 private var held = Set<String>()
 mutating func reset() { held.removeAll() }
 mutating func consume(profile: ReceiverMappingProfile, button: UInt8, isDown: Bool, enrolled: Set<String>) -> ReceiverMappingDecision {
  let source = profile.source(button:button)
  let denied = ReceiverMappingDecision(source:source,learn:false,execute:false)
  guard (1...6).contains(profile.slot), (3...16).contains(button) else { return denied }
  if !isDown { held.remove(source); return denied }
  guard held.insert(source).inserted, listening, enrolled.contains(profile.id) else { return denied }
  return ReceiverMappingDecision(source:source,learn:true,execute:executionEnabled)
 }
}
struct NamedShortcutKey: Identifiable {
 let id: String
 let label: String
 let keyCode: UInt16
 // Fixed macOS virtual key constants verified in HIToolbox/Events.h.
 static let all: [NamedShortcutKey] = [
  .init(id:"left",label:"Flecha izquierda",keyCode:123),
  .init(id:"right",label:"Flecha derecha",keyCode:124),
  .init(id:"up",label:"Flecha arriba",keyCode:126),
  .init(id:"down",label:"Flecha abajo",keyCode:125),
  .init(id:"space",label:"Espacio",keyCode:49), .init(id:"return",label:"Retorno",keyCode:36),
  .init(id:"tab",label:"Tabulador",keyCode:48), .init(id:"escape",label:"Escape",keyCode:53),
  .init(id:"f1",label:"F1",keyCode:122), .init(id:"f2",label:"F2",keyCode:120),
  .init(id:"f3",label:"F3",keyCode:99), .init(id:"f4",label:"F4",keyCode:118),
  .init(id:"f5",label:"F5",keyCode:96), .init(id:"f6",label:"F6",keyCode:97),
  .init(id:"f7",label:"F7",keyCode:98), .init(id:"f8",label:"F8",keyCode:100),
  .init(id:"f9",label:"F9",keyCode:101), .init(id:"f10",label:"F10",keyCode:109),
  .init(id:"f11",label:"F11",keyCode:103), .init(id:"f12",label:"F12",keyCode:111)
 ]
}
