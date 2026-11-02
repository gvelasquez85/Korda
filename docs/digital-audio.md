# Volumen digital experimental

Korda 0.9.1 incorpora una ruta de control por software para salidas digitales mediante CoreAudio en macOS 14.2 o posterior. Debe activarse explícitamente para la salida identificada que se quiere controlar; las acciones se vinculan a su UID.

La ruta procesa el audio localmente para aplicar volumen. No graba el audio ni lo sube a un servicio. macOS exige el permiso de audio del sistema para esta función. La implementación admite únicamente Float32 intercalado mono o estéreo; otros formatos no deben considerarse compatibles.

Pausar, salir de Korda o poner el Mac en reposo detiene esta ruta. Antes de usarla habitualmente, hay que probar el sonido, el volumen, silenciar, la restauración y los cambios de salida en el equipo real.

Las pruebas audibles de hardware siguen pendientes. Esta función es experimental y no acredita compatibilidad con todas las salidas HDMI, DisplayPort, USB o interfaces de audio. Si una salida o formato no se admite, no se debe presentar como un control funcional.

La ruta convierte frecuencias distintas con AudioConverter; por ejemplo, una entrada de 44.100 Hz y una salida DisplayPort de 48.000 Hz. Las pruebas sintéticas verifican duración y frecuencia de una señal de 1 kHz, sin modificar el formato del dispositivo físico. La prueba audible sigue pendiente.
