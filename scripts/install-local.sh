#!/bin/zsh
set -eu
cd "${0:A:h:h}"
korda_candidate="${1:-build/redesign/Korda.app}"
korda_destination=/Applications/Korda.app
if pgrep -f '^/Applications/Korda.app/Contents/MacOS/Korda$' >/dev/null; then
  print -u2 'Sal de Korda desde su menú y espera a que restaure las teclas antes de instalar. No se cambió la app.'
  exit 2
fi
codesign --verify --deep --strict "$korda_candidate"
plutil -lint "$korda_candidate/Contents/Info.plist"
mkdir -p build/archive
korda_install_backup=$(mktemp -d build/archive/korda-install.XXXXXX)
korda_backup="$korda_install_backup/previous.app"
if [[ -e "$korda_destination" ]]; then mv "$korda_destination" "$korda_backup"; fi
if ! ditto "$korda_candidate" "$korda_destination" || ! codesign --verify --deep --strict "$korda_destination"; then
  if [[ -e "$korda_destination" ]]; then mv "$korda_destination" "$korda_install_backup/failed.app"; fi
  if [[ -e "$korda_backup" ]]; then mv "$korda_backup" "$korda_destination"; fi
  exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$korda_destination"
print 'Korda instalada. Preferencias conservadas; la compilación nueva puede requerir reautorizar permisos.'
