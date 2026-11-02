# Korda

Aplicación nativa experimental para configurar controles de dispositivos en macOS. Versión en preparación: 0.10.0; todavía no es una versión 1.0 validada.

Idioma de la aplicación: **Ajustes → General → Idioma**, con opciones Sistema, Español y English.

## Funcionalidades

- Inventario de dispositivos USB, interfaces HID y cámaras. Los dispositivos sin configuración implementada muestran información.
- Identificación HID++ de periféricos compatibles detrás de receptores y administración de emparejamiento.
- Asignaciones de botones y teclas compatibles a acciones multimedia, atajos de teclado y apertura de una aplicación elegida.
- Asignaciones persistentes, editor por dispositivo y sección de ajustes y diagnósticos.
- Barra de menús: pausar, reanudar, abrir ajustes, salir e inicio opcional con macOS.
- Reemplazo exclusivo experimental para controles HID++ 1B04 compatibles, con comprobación del desvío y restauración al pausar o salir normalmente.

Al cerrar la ventana, Korda permanece en la barra de menús y oculta su icono del Dock. Abrir ajustes vuelve a mostrarlo.

## Compatibilidad y límites

La compilación actual apunta a macOS 14 o posterior en Intel. Apple Silicon no está validado. Las pruebas físicas realizadas durante el desarrollo incluyen controles del M570 y funciones multimedia de K540/K400r; no constituyen garantía para todos los modelos o receptores.

El reemplazo exclusivo necesita una identificación reciente y capacidades compatibles del control. Su validación física completa está pendiente. La recuperación tras cierre forzado, caída del proceso o desconexión no está terminada: durante las pruebas se debe usar **Pausar** o **Salir** y esperar la restauración. Las acciones adicionales conservan la función original.

Las cámaras se inventarían; no se ofrecen todavía ajustes UVC. Las teclas de escritura ordinarias y Fn no se remapean. La existencia de un dispositivo en el inventario no implica que sus ajustes estén implementados.

El control de volumen digital experimental utiliza CoreAudio en macOS 14.2 o posterior y requiere permiso de audio del sistema y activación explícita. Sólo admite audio Float32 intercalado mono o estéreo. Las acciones se vinculan al UID de la salida elegida. Se detiene al pausar, salir o entrar en reposo. Las pruebas audibles en hardware siguen pendientes; no se declara compatibilidad universal. Consulta [Volumen digital](docs/digital-audio.md).

## Compilar

Se necesitan macOS y las herramientas de desarrollo de Apple con Swift:

```sh
./build.sh
```

El resultado es `build/Korda.app`. La firma local es ad hoc, sin notarización ni certificado Developer ID. Esta configuración de desarrollo no equivale a una distribución pública firmada. El script contiene una adaptación local del módulo Swift de las Command Line Tools; revisar su aplicabilidad en otro equipo.

Para ejecutar las pruebas del modelo y captura, el propio script de compilación ejecuta `Tests/MappingTests.swift`. Hay pruebas adicionales en `Tests/` y scripts de decodificación en la raíz; la presencia de estos archivos no acredita que toda la matriz de hardware haya sido probada.

## Permisos y privacidad

Monitorización de entrada permite recibir controles y Accesibilidad permite emitir atajos y acciones multimedia. macOS puede exigir volver a autorizar una compilación nueva firmada ad hoc. Korda no concede estos permisos por sí misma ni instala un controlador. Su política de captura excluye el texto ordinario escrito; los diagnósticos de hardware deben tratarse como información local y revisarse antes de compartirlos.

## Estado de publicación

El destino aprobado es el repositorio público gvelasquez85/Korda. El código se ofrece bajo [licencia MIT](LICENSE). El código se publica como desarrollo experimental. Una release estable 1.0 y la distribución notarizada siguen pendientes.

Korda es un proyecto independiente; los nombres de modelos identifican hardware y no implican afiliación ni respaldo del fabricante.

El cambio de idioma se aplica a la interfaz y a los mensajes nuevos. El historial de diagnósticos puede conservar el idioma anterior hasta actualizarse. Los diálogos propios de macOS siguen el idioma del sistema.
