# Korda

[Español](README.es.md) · English

Experimental native macOS app for configuring compatible device controls. Current development version: **0.10.0**. This is not a validated 1.0 release.

## What you can do

- Browse USB devices, HID interfaces, audio outputs and cameras, with readable device names where identification is available.
- Identify compatible wireless devices behind receivers using HID++ and manage pairing.
- Assign supported buttons and keys to media actions, keyboard shortcuts, or an application you choose.
- Keep assignments running from the menu bar, pause them, open settings, quit, or optionally start Korda with macOS. Closing settings hides the Dock icon; reopening settings restores it.
- Experimentally replace compatible HID++ 1B04 controls, with diversion readback and restoration on normal pause or quit.
- Enable optional software volume and mute for a chosen digital audio output, then assign Korda volume actions to a device control.
- Choose English, Spanish, or the system language under **Settings → General → Language**.

## Requirements and limits

The current build targets **Intel Macs with macOS 14 or later**. Apple Silicon has not been validated. Digital audio control requires **macOS 14.2 or later**.

Physical development tests have covered M570 buttons and K540/K400r media controls. They do not establish compatibility with every model or receiver.

Exclusive key replacement requires a fresh device identification and compatible control capabilities. Full hardware validation is pending. Recovery after a forced quit, crash or disconnection is not finished: use **Pause** or **Quit** and wait for restoration during testing. Additional actions retain the original behavior.

Ordinary typing keys and Fn are not remapped. Cameras are inventoried; UVC image controls are not implemented. Appearing in the device list does not mean every hardware setting can be changed.

Digital audio processing is experimental. It requires explicit activation and macOS system audio access. It currently supports interleaved mono/stereo Float32 PCM, including sample-rate conversion such as 44.1 kHz to 48 kHz. Actions target the selected output UID. Processing stops on pause, quit or sleep. Audible hardware validation is still pending; universal HDMI, DisplayPort and USB compatibility is not claimed.

## Build and test

Install Apple's command line developer tools, then run:

```sh
./build.sh
./scripts/test.sh
```

The app is written to `build/Korda.app`. Tests do not start system audio capture or write device firmware settings. The build includes a local Swift module-map workaround; its applicability on another development machine must be checked.

`./release.sh` creates an optimized Intel build, runs checks and packages the app. Local builds use an **ad hoc signature**, without Developer ID signing or notarization. This is not a notarized public installer.

Language changes apply to the interface and new messages. Existing diagnostic history may keep its previous language until refreshed. macOS-owned dialogs use the system language.

## Privacy and permissions

Input Monitoring receives device controls. Accessibility emits keyboard shortcuts and system media actions. Digital volume processing also needs system audio access. macOS may require reauthorization after a new ad hoc build. Korda does not grant its own permissions or install a driver.

Digital audio is processed locally in memory; it is not recorded or uploaded. Ordinary typed text is excluded by the input capture policy. Hardware diagnostics remain local and should be reviewed before sharing.

## Status and license

Source is published at [gvelasquez85/Korda](https://github.com/gvelasquez85/Korda) under the [MIT license](LICENSE). A stable 1.0 release and notarized distribution remain pending.

Korda is an independent project. Hardware model names identify devices and do not imply manufacturer affiliation or endorsement.
