import SwiftUI

struct DigitalAudioPanel:View {
 @ObservedObject private var language = LanguageSettings.shared
 @ObservedObject var controller:DigitalAudioController
 var outputUID:String? = nil
 @State private var selection = ""
 private var chosen:String { outputUID ?? selection }
 private var controlsOtherOutput:Bool { controller.activeOutputUID != nil && controller.activeOutputUID != chosen }
 var body:some View {
  GroupBox(L10n.tr("Volumen de la salida · Korda")) {
   VStack(alignment:.leading,spacing:14) {
    Text(L10n.tr("Controla el volumen incluso cuando macOS lo muestra bloqueado en HDMI, DisplayPort o una salida USB compatible.")).font(.callout)
    if outputUID == nil {
     Picker(L10n.tr("Salida"),selection:$selection) {
      Text(L10n.tr("Selecciona una salida")).tag("")
      ForEach(controller.outputs) { output in Text(output.name).tag(output.id) }
     }
    }
    Text(L10n.display(controller.status)).font(.callout).textSelection(.enabled)
    if let active = controller.activeOutputUID {
     Label(L10n.tr("Procesando: ") + (controller.outputs.first(where:{$0.id == active})?.name ?? L10n.tr("salida elegida")),systemImage:"waveform").foregroundStyle(.mint)
    }
    if controlsOtherOutput { Text(L10n.tr("El control está activo en otra salida. Sus ajustes se administran desde esa salida.")).font(.caption).foregroundStyle(.secondary) }
    HStack {
     Text(L10n.tr("Volumen"))
     Slider(value:Binding(get:{controller.level},set:{controller.setLevel($0)}),in:0...1).accessibilityLabel(L10n.tr("Volumen digital Korda")).disabled(controlsOtherOutput)
     Text(String(Int(controller.level * 100)) + "%").monospacedDigit().frame(width:48,alignment:.trailing)
    }
    HStack {
     Button(controller.isMuted ? L10n.tr("Activar sonido") : L10n.tr("Silenciar")) { controller.toggleMute() }.disabled(controller.activeOutputUID == nil || controlsOtherOutput)
     Spacer()
     if controller.activeOutputUID != nil || controller.hasRestorationObligations {
      Button(controlsOtherOutput ? L10n.tr("Desactivar salida activa") : L10n.tr("Desactivar y restaurar audio")) { _ = controller.stop() }
     } else {
      Button(L10n.tr("Activar control digital")) { do { try controller.start(outputUID:chosen) } catch { /* Controller exposes a readable error. */ } }.disabled(chosen.isEmpty)
     }
     Button(L10n.tr("Actualizar salidas")) { controller.refresh() }
    }
    Text(L10n.tr("Al activar, macOS puede pedir acceso al audio del sistema. Korda lo atenúa en memoria: no graba ni envía audio. Pausar o salir restaura la ruta original; después debes activarlo de nuevo.")).font(.caption).foregroundStyle(.secondary)
    Text(L10n.tr("Para usar una tecla: elige su dispositivo, selecciona el control y asigna Subir volumen, Bajar volumen o Silenciar de Korda con esta salida. El reemplazo de la tecla original depende de la compatibilidad del control.")).font(.caption).foregroundStyle(.secondary)
    Text(L10n.tr("Compatibilidad inicial: macOS 14.2 o posterior y PCM Float32 mono/estéreo intercalado. El audio protegido y otros formatos requieren validación. El volumen de Korda atenúa la señal; el amplificador o monitor conserva su propio nivel.")).font(.caption).foregroundStyle(.secondary)
   }.frame(maxWidth:.infinity,alignment:.leading).padding(8)
  }
 }
}
