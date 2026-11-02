# Abrir una aplicación desde un control
En Dispositivos, elige el dispositivo y su tecla o botón. En Acción selecciona «Abrir aplicación…», pulsa «Elegir aplicación…» y elige una aplicación de macOS. «Probar acción seleccionada» permite comprobar la apertura antes de guardar. «Guardar asignación» vincula la aplicación con el control.

Si la aplicación ya está abierta, macOS la activa. Editar una asignación permite cambiar la aplicación. Korda conserva un marcador, la ubicación y el identificador de la aplicación para localizarla si cambia de ubicación; si no puede encontrarla, muestra un error y permite volver a elegirla.

La acción no ejecuta comandos de terminal ni necesita un atajo de teclado. Recibir el control sigue requiriendo los permisos de captura de Korda. El reemplazo exclusivo de teclas conserva sus requisitos y limitaciones de compatibilidad; elegir una app no convierte una ruta adicional en exclusiva.

Validación: prueba de persistencia y lectura de reglas antiguas en Tests/MappingTests.swift. La prueba física de cada tecla depende del dispositivo conectado.
