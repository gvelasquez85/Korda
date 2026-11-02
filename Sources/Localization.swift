import Foundation
import Combine

/// Persisted language identifiers are independent of action and device identifiers.
final class LanguageSettings:ObservableObject {
 static let shared=LanguageSettings()
 private let defaults:UserDefaults
 private let preferredLanguages:[String]
 @Published var preference:String {didSet{defaults.set(preference,forKey:"interfaceLanguage")}}
 init(defaults:UserDefaults = .standard,preferredLanguages:[String] = Locale.preferredLanguages) {
  self.defaults=defaults;self.preferredLanguages=preferredLanguages
  let value=defaults.string(forKey:"interfaceLanguage") ?? "system"
  preference=["system","es","en"].contains(value) ? value : "system"
 }
 var languageCode:String {
  let override=ProcessInfo.processInfo.environment["KORDA_LANGUAGE"]
  return LocalizationCatalog.resolve(override ?? preference,preferred:preferredLanguages)
 }
}
struct LocalizationCatalog {
 let english:[String:String]
 let spanish:[String:String]
 init(resourceRoot:URL)throws {
  func read(_ language:String)throws->[String:String] {
   let url=resourceRoot.appendingPathComponent(language+".lproj/Localizable.strings")
   let data=try Data(contentsOf:url)
   guard let dictionary=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:String] else {
    throw NSError(domain:"Korda.Localization",code:1,userInfo:[NSLocalizedDescriptionKey:"Invalid localization catalog"])
   }
   return dictionary
  }
  english=try read("en");spanish=try read("es")
 }
 static func resolve(_ preference:String,preferred:[String])->String {
  if preference=="es" || preference=="en" {return preference}
  return preferred.first?.lowercased().hasPrefix("es")==true ? "es":"en"
 }
 static func markers(_ text:String)->[String] {
  var values:[String]=[];var cursor=text.startIndex
  while let start=text.range(of:"{{",range:cursor..<text.endIndex),let end=text.range(of:"}}",range:start.upperBound..<text.endIndex) {
   let index=String(text[start.upperBound..<end.lowerBound])
   if Int(index) != nil {values.append(index)}
   cursor=end.upperBound
  }
  return values.sorted()
 }
 func text(_ key:String,language:String,arguments:[String])->String {
  let template=(language=="es" ? spanish[key]:english[key]) ?? key
  return Self.interpolate(template,arguments:arguments)
 }
 /// Single pass: device names and error messages containing marker-like text stay literal.
 static func interpolate(_ template:String,arguments:[String])->String {
  var result="";var cursor=template.startIndex
  while let start=template.range(of:"{{",range:cursor..<template.endIndex),let end=template.range(of:"}}",range:start.upperBound..<template.endIndex) {
   result+=template[cursor..<start.lowerBound]
   let token=String(template[start.upperBound..<end.lowerBound])
   if let index=Int(token),arguments.indices.contains(index) {result+=arguments[index]}
   else {result+=template[start.lowerBound..<end.upperBound]}
   cursor=end.upperBound
  }
  result+=template[cursor...];return result
 }
}
enum L10n {
 private static let catalog:LocalizationCatalog? = {
  let root=ProcessInfo.processInfo.environment["KORDA_LOCALIZATION_RESOURCES"].map{URL(fileURLWithPath:$0)} ?? Bundle.main.resourceURL ?? Bundle.main.bundleURL
  return try? LocalizationCatalog(resourceRoot:root)
 }()
 /// Re-render cached static status messages; event history keeps its original language.
 static func display(_ message:String)->String {
  guard let catalog else {return message}
  let key=catalog.spanish[message] != nil ? message:catalog.english.first(where:{$0.value==message})?.key
  return key.map{catalog.text($0,language:LanguageSettings.shared.languageCode,arguments:[])} ?? message
 }
 static func tr(_ key:String,_ arguments:String...)->String {
  catalog?.text(key,language:LanguageSettings.shared.languageCode,arguments:arguments) ?? LocalizationCatalog.interpolate(key,arguments:arguments)
 }
}
