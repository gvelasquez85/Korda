# Preparación de publicación

## Contenido previsto

Publicar únicamente código propio de Sources/, pruebas de Tests/, recursos originales de Resources/, scripts de compilación/instalación y documentación pública revisada. Revisar el diff o una lista explícita de archivos antes del primer commit.

.gitignore excluye build/, analysis/, evidence/, paquetes de aplicación, instaladores, registros, variables de entorno y notas históricas internas. analysis/ contiene un binario extraído y su desensamblado: no deben subirse. evidence/ contiene inventarios y detalles del Mac y dispositivos. build/ incluye copias de preferencias y artefactos de desarrollo. Ignorar estos directorios no los elimina localmente.

Las notas históricas docs/ quedan excluidas por defecto, salvo la guía de apertura de aplicaciones y este documento. No publicar automáticamente toda la carpeta. .gitignore no retira archivos que ya estén versionados; comprobar git ls-files antes de subir.

## Pendientes

- Destino aprobado: gvelasquez85/Korda público. Licencia MIT aprobada; archivo LICENSE añadido. Completar acceso a GitHub antes de publicar.
- Revisar recursos gráficos y procedencia del código y dependencias; no borrar atribuciones exigibles ni cambiar nombres para aparentar eliminar obligaciones.
- Revisión final de secretos, rutas personales e identificadores en el conjunto exacto que se subirá.
- Cerrar o declarar limitaciones de reemplazo exclusivo y recuperación tras caída.
- Validar el nuevo control digital de audio antes de anunciarlo.
- Definir distribución Intel/Apple Silicon, certificado Developer ID y notarización si se busca instalación pública sencilla.
- Ejecutar la matriz de pruebas en un entorno limpio y validar instalación/permisos.
- Publicar como desarrollo experimental mientras persistan límites; no etiquetar v1.0.

Se añadió la licencia MIT autorizada. No se ha creado repositorio, commit ni publicación durante esta preparación.
