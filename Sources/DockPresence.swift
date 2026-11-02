import AppKit
import SwiftUI

/// Keep the Dock entry only while the settings window is available.
struct SettingsWindowPresence:NSViewRepresentable {
 func makeNSView(context:Context)->NSView { SettingsWindowTracker() }
 func updateNSView(_ nsView:NSView,context:Context) {}
}
private final class SettingsWindowTracker:NSView {
 private var closeObserver:NSObjectProtocol?
 override func viewDidMoveToWindow() {
  super.viewDidMoveToWindow()
  if let closeObserver { NotificationCenter.default.removeObserver(closeObserver);self.closeObserver=nil }
  guard let window else{return}
  NSApp.setActivationPolicy(.regular)
  closeObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:window,queue:.main) { _ in
   // The status item and capture services remain alive under accessory policy.
   DispatchQueue.main.async {
    guard !NSApp.windows.contains(where:{$0.isVisible && $0.identifier?.rawValue == "korda-settings"}) else{return}
    NSApp.setActivationPolicy(.accessory)
   }
  }
 }
 deinit {if let closeObserver {NotificationCenter.default.removeObserver(closeObserver)}}
}
