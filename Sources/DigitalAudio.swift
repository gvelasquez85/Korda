import Foundation
import CoreAudio
import Combine

@_silgen_name("korda_dsp_create_rates") private func dspCreateRates(_ channels:UInt32,_ inputRate:Double,_ outputRate:Double)->UnsafeMutableRawPointer?
@_silgen_name("korda_dsp_destroy") private func dspDestroy(_ pointer:UnsafeMutableRawPointer)
@_silgen_name("korda_dsp_gain") private func dspGain(_ pointer:UnsafeMutableRawPointer,_ gain:Float)
@_silgen_name("korda_dsp_frames") private func dspFrames(_ pointer:UnsafeMutableRawPointer)->UInt
@_silgen_name("korda_dsp_fault") private func dspFault(_ pointer:UnsafeMutableRawPointer)->Int32
@_silgen_name("korda_audio_callback") private func dspCallback(_ device:AudioObjectID,_ now:UnsafePointer<AudioTimeStamp>,_ input:UnsafePointer<AudioBufferList>,_ inputTime:UnsafePointer<AudioTimeStamp>,_ output:UnsafeMutablePointer<AudioBufferList>,_ outputTime:UnsafePointer<AudioTimeStamp>,_ context:UnsafeMutableRawPointer?)->OSStatus

struct AudioOutputInfo:Identifiable,Equatable {
 let id:String
 let name:String
 let deviceID:AudioObjectID
 static func inventory()->[AudioOutputInfo] {
  var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:0)
  var size:UInt32=0
  guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size)==0 else{return []}
  var devices=[AudioObjectID](repeating:0,count:Int(size)/4)
  guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&devices)==0 else{return []}
  return devices.compactMap { device in
   var streams=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreams,mScope:kAudioDevicePropertyScopeOutput,mElement:0);var count:UInt32=0
   guard AudioObjectGetPropertyDataSize(device,&streams,0,nil,&count)==0,count>0,
         let uid=audioString(device,kAudioDevicePropertyDeviceUID),let name=audioString(device,kAudioObjectPropertyName),
         !uid.hasPrefix("local.german.korda.audio.") else{return nil}
   return AudioOutputInfo(id:uid,name:name,deviceID:device)
  }
 }
}
private func audioString(_ object:AudioObjectID,_ selector:AudioObjectPropertySelector)->String? {
 var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:0)
 var value:CFString?;var size=UInt32(MemoryLayout<CFString?>.size)
 guard withUnsafeMutablePointer(to:&value,{ AudioObjectGetPropertyData(object,&address,0,nil,&size,$0) })==0 else{return nil}
 return value as String?
}
enum DigitalAudioError:LocalizedError {
 case failure(String,OSStatus),unsupported(String)
 var errorDescription:String? {switch self{case .failure(let operation,let status):return "\(operation): \(status)";case .unsupported(let message):return message}}
}
private func checked(_ status:OSStatus,_ operation:String)throws{if status != 0{throw DigitalAudioError.failure(operation,status)}}
final class DigitalAudioController:ObservableObject {
 @Published private(set) var outputs:[AudioOutputInfo]=[]
 @Published private(set) var activeOutputUID:String?
 @Published private(set) var level:Double=0.5
 @Published private(set) var isMuted=false
 @Published private(set) var status="Control digital desactivado."
 var hasRestorationObligations:Bool {tap != 0 || aggregate != 0 || proc != nil || dsp != nil}
 private var tap:AudioObjectID=0
 private var aggregate:AudioObjectID=0
 private var proc:AudioDeviceIOProcID?
 private var dsp:UnsafeMutableRawPointer?
 private var timer:Timer?
 private var started=false
 var isProcessing:Bool { started }
 private var activationTime=Date.distantPast
 init(){refresh()}
 deinit{cleanup()}
 func refresh(){outputs=AudioOutputInfo.inventory();if let uid=activeOutputUID,!outputs.contains(where:{$0.id==uid}){if stop(){status="Salida desconectada. Control digital detenido."}}}
 func start(outputUID:String)throws {
  guard stop() else {throw DigitalAudioError.unsupported(status)}
  guard #available(macOS 14.2,*) else{throw DigitalAudioError.unsupported("El control digital requiere macOS 14.2 o posterior.")}
  do{try activate(outputUID:outputUID)}catch{if cleanup(){status=error.localizedDescription};throw error}
 }
 @available(macOS 14.2,*) private func activate(outputUID:String)throws {
  refresh()
  guard let output=outputs.first(where:{$0.id==outputUID}) else{throw DigitalAudioError.unsupported("Salida no disponible.")}
  var pid=ProcessInfo.processInfo.processIdentifier
  var own:AudioObjectID=0;var size=UInt32(MemoryLayout<AudioObjectID>.size)
  var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyTranslatePIDToProcessObject,mScope:kAudioObjectPropertyScopeGlobal,mElement:0)
  try checked(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,UInt32(MemoryLayout<pid_t>.size),&pid,&size,&own),"Identificar proceso de audio")
  guard own != 0 else{throw DigitalAudioError.unsupported("No se pudo excluir Korda de la captura.")}
  let description=CATapDescription(__excludingProcesses:[NSNumber(value:own)],andDeviceUID:output.id,withStream:0)
  description.name="Korda · control digital";description.isPrivate=true;description.muteBehavior = .mutedWhenTapped
  try checked(AudioHardwareCreateProcessTap(description,&tap),"Crear captura de audio")
  let tapFormat=try format(tap,selector:kAudioTapPropertyFormat,scope:kAudioObjectPropertyScopeGlobal)
  try validate(tapFormat)
  let dictionary:[String:Any]=[
   kAudioAggregateDeviceNameKey:"Korda · "+output.name,
   kAudioAggregateDeviceUIDKey:"local.german.korda.audio."+UUID().uuidString,
   kAudioAggregateDeviceIsPrivateKey:true,
   kAudioAggregateDeviceMainSubDeviceKey:output.id,
   kAudioAggregateDeviceSubDeviceListKey:[[kAudioSubDeviceUIDKey:output.id]],
   kAudioAggregateDeviceTapListKey:[[kAudioSubTapUIDKey:description.uuid.uuidString,kAudioSubTapDriftCompensationKey:true]],
   kAudioAggregateDeviceTapAutoStartKey:false]
  try checked(AudioHardwareCreateAggregateDevice(dictionary as CFDictionary,&aggregate),"Crear ruta de audio")
  let outFormat=try format(aggregate,selector:kAudioDevicePropertyStreamFormat,scope:kAudioDevicePropertyScopeOutput)
  try validate(outFormat)
  guard outFormat.mChannelsPerFrame==tapFormat.mChannelsPerFrame else{throw DigitalAudioError.unsupported("Los formatos de entrada y salida no coinciden.")}
  guard let state=dspCreateRates(tapFormat.mChannelsPerFrame,tapFormat.mSampleRate,outFormat.mSampleRate) else{throw DigitalAudioError.unsupported("Sin memoria para audio.")}
  dsp=state;updateGain()
  try checked(AudioDeviceCreateIOProcID(aggregate,dspCallback,state,&proc),"Preparar procesamiento")
  try checked(AudioDeviceStart(aggregate,proc),"Iniciar control digital")
  activationTime=Date()
  started=true;activeOutputUID=output.id;status="Ruta iniciada; esperando señal de audio: "+output.name
  timer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self] _ in
   guard let self,let state=self.dsp else{return}
   if Date().timeIntervalSince(self.activationTime)>30,dspFrames(state)==0 {if self.stop(){self.status="No se recibieron muestras. Reproduce audio, revisa permiso de audio del sistema y vuelve a activar."};return}
   if dspFault(state) != 0 {if self.stop(){self.status="Formato de audio cambiado. Control detenido."};return}
   if dspFrames(state)>0 {self.status="Control digital activo: "+output.name}
   guard let current=try? self.format(self.aggregate,selector:kAudioDevicePropertyStreamFormat,scope:kAudioDevicePropertyScopeOutput),
         let input=try? self.format(self.tap,selector:kAudioTapPropertyFormat,scope:kAudioObjectPropertyScopeGlobal),
         current.mSampleRate==outFormat.mSampleRate,current.mChannelsPerFrame==outFormat.mChannelsPerFrame,
         current.mFormatFlags==outFormat.mFormatFlags,current.mBitsPerChannel==outFormat.mBitsPerChannel,
         input.mSampleRate==tapFormat.mSampleRate,input.mChannelsPerFrame==tapFormat.mChannelsPerFrame,
         input.mFormatFlags==tapFormat.mFormatFlags,input.mBitsPerChannel==tapFormat.mBitsPerChannel else {
    if self.stop(){self.status="Formato de audio cambiado o no disponible. Control detenido."};return
   }
   self.refresh()
  }
 }
 private func format(_ object:AudioObjectID,selector:AudioObjectPropertySelector,scope:AudioObjectPropertyScope)throws->AudioStreamBasicDescription {
  var address=AudioObjectPropertyAddress(mSelector:selector,mScope:scope,mElement:0);var value=AudioStreamBasicDescription();var size=UInt32(MemoryLayout.size(ofValue:value))
  try checked(AudioObjectGetPropertyData(object,&address,0,nil,&size,&value),"Leer formato de audio");return value
 }
 private func validate(_ format:AudioStreamBasicDescription)throws {
  guard format.mFormatID==kAudioFormatLinearPCM,format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
        format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
        format.mBitsPerChannel==32,(1...2).contains(format.mChannelsPerFrame),
        format.mBytesPerFrame==4*format.mChannelsPerFrame,format.mSampleRate>0 else{
   throw DigitalAudioError.unsupported("Esta salida no ofrece PCM Float32 intercalado mono/estéreo compatible.")
  }
 }
 @discardableResult func stop()->Bool{guard cleanup() else{return false};activeOutputUID=nil;status="Control digital desactivado; ruta original restaurada.";return true}
 @discardableResult private func cleanup()->Bool{
  timer?.invalidate();timer=nil
  if aggregate != 0,let proc {
   if started {
    let result=AudioDeviceStop(aggregate,proc)
    guard result==0 else {status="No se confirmó la parada de audio (\(result)). Recursos retenidos; reintenta detener.";return false}
   }
   started=false;activeOutputUID=nil
   let result=AudioDeviceDestroyIOProcID(aggregate,proc)
   guard result==0 else{status="No se liberó el procesador de audio (\(result)). Recursos retenidos.";return false}
  }
  started=false;activeOutputUID=nil;proc=nil
  if aggregate != 0 {let result=AudioHardwareDestroyAggregateDevice(aggregate);guard result==0 else{status="No se pudo liberar la ruta de audio (\(result)). Reintenta detener.";return false};aggregate=0}
  if #available(macOS 14.2,*),tap != 0 {let result=AudioHardwareDestroyProcessTap(tap);guard result==0 else{status="No se pudo liberar la captura (\(result)). Reintenta detener.";return false};tap=0}
  if let dsp{dspDestroy(dsp)};dsp=nil
  return true
 }
 static func clampedLevel(_ value:Double)->Double{value.isFinite ? min(1,max(0,value)):0}
 func setLevel(_ value:Double){level=Self.clampedLevel(value);updateGain()}
 func adjust(step:Double){setLevel(level+step);isMuted=false;updateGain()}
 func toggleMute(){isMuted.toggle();updateGain()}
 private func updateGain(){if let dsp{dspGain(dsp,isMuted ? 0:Float(level))}}
}
