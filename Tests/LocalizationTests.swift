import Foundation
@main struct LocalizationChecks {
 static func main() throws {
  let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
  let catalog=try LocalizationCatalog(resourceRoot:root)
  precondition(catalog.english.count > 350)
  precondition(Set(catalog.english.keys)==Set(catalog.spanish.keys))
  let printf = try NSRegularExpression(pattern:#"%(?:[0-9]+\$)?[-+ #0]*(?:[0-9]+|\*)?(?:\.(?:[0-9]+|\*))?(?:ll|l|h|hh|z|t|j)?[a-zA-Z%@]"#)
  func formats(_ value:String)->[String] { printf.matches(in:value,range:NSRange(value.startIndex...,in:value)).map{String(value[Range($0.range,in:value)!])} }
  for (key,value) in catalog.english {
   precondition(formats(key)==formats(value),"Changed printf tokens: \(key)")
   precondition(LocalizationCatalog.markers(key)==LocalizationCatalog.markers(value),"Changed interpolation: \(key)")
  }
  precondition(LocalizationCatalog.resolve("system",preferred:["es-CO","en-US"])=="es")
  precondition(LocalizationCatalog.resolve("system",preferred:["fr-FR"])=="en")
  precondition(LocalizationCatalog.resolve("en",preferred:["es"])=="en")
  precondition(catalog.text("Dispositivos",language:"en",arguments:[])=="Devices")
  precondition(catalog.text("Página {{0}} · botón {{1}}",language:"en",arguments:["12","233"])=="Page 12 · button 233")
  precondition(catalog.text("Página {{0}} · botón {{1}}",language:"es",arguments:["12","233"])=="Página 12 · botón 233")
  precondition(catalog.text("Página {{0}} · botón {{1}}",language:"en",arguments:["{{1}}","100% / café"])=="Page {{1}} · button 100% / café","Arguments must not be interpreted as placeholders")
  precondition(catalog.text("receiver|slot=1",language:"en",arguments:[])=="receiver|slot=1")
  let suite="korda.localization.tests."+UUID().uuidString
  let defaults=UserDefaults(suiteName:suite)!
  defer{defaults.removePersistentDomain(forName:suite)}
  let settings=LanguageSettings(defaults:defaults,preferredLanguages:["fr"])
  precondition(settings.languageCode=="en")
  settings.preference="es"
  precondition(LanguageSettings(defaults:defaults,preferredLanguages:["en"]).languageCode=="es")
  print("Localization checks passed: bilingual catalog, interpolation integrity, literal arguments, fallback and isolated preference persistence")
 }
}
