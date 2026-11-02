import AppKit
let root = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1024,pixelsHigh:1024,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
let ctx = NSGraphicsContext(bitmapImageRep:rep)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
NSColor.clear.setFill(); NSRect(x:0,y:0,width:1024,height:1024).fill()
let tile = NSBezierPath(roundedRect:NSRect(x:80,y:80,width:864,height:864),xRadius:192,yRadius:192)
NSColor(calibratedRed:0.055,green:0.11,blue:0.15,alpha:1).setFill(); tile.fill()
let k = NSBezierPath(); k.lineWidth=82; k.lineCapStyle = .round; k.lineJoinStyle = .round
k.move(to:NSPoint(x:354,y:300)); k.line(to:NSPoint(x:354,y:724))
k.move(to:NSPoint(x:656,y:714)); k.line(to:NSPoint(x:370,y:510)); k.line(to:NSPoint(x:656,y:310))
NSColor(calibratedRed:0.22,green:0.91,blue:0.76,alpha:1).setStroke(); k.stroke()
NSColor(calibratedRed:0.91,green:1,blue:0.98,alpha:1).setFill()
for p in [NSPoint(x:354,y:724),NSPoint(x:656,y:714),NSPoint(x:656,y:310)] { NSBezierPath(ovalIn:NSRect(x:p.x-28,y:p.y-28,width:56,height:56)).fill() }
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root + "/Resources/Korda.png"))
