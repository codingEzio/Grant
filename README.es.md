# Grant

<p><img src="Resources/README-icon.svg" width="96" height="96" alt="Grant"></p>

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

Estilos nativos para la autorización de administrador de macOS. La versión 0.2.3 es un candidato local: incluye una aplicación de ajustes, un Authorization Plug-in y un instalador de sistema protegido. Instalar la aplicación y activar el sistema son pasos separados.

Las cuatro fuentes se obtienen por separado; Google Fonts y Compact 0.1.1 están fijadas por hash. La primera descarga requiere red. Los derechos de marca de productos que incluyan fuentes no están verificados.

## Estilos y controles

Hay seis estilos: Paper Punch, Dot Instrument, Swiss Signal, Hard Edge, Blueprint y Setup Original. Ofrecen papel con título condensado, tipografía de puntos real, azul, amarillo con sombra, plantillas y la tabla original. Admiten apariencia clara／oscura／del sistema, tipografía Theme／System e interfaz en inglés, 简体中文 y 繁體中文. Este README en español no añade otro idioma a la interfaz.

La tarjeta normal mide 440×184pt; Setup Original, 560×460pt. El campo de cuenta añade 36pt al expandirse. Return envía y Escape cancela. La vista previa usa datos sintéticos y desactiva la contraseña; la autorización real usa el contexto recibido, sin inventar detalles de una operación.

Puedes configurar fuentes y alternativas por estilo y apariencia. La aplicación compilada incluye Doto, Compact, Black Ops One y Saira Stencil One con sus avisos; no se descargan ni instalan fuentes. Las caras personales o del sistema opcionales no se redistribuyen. Consulta la [guía de tipografía](docs/TYPOGRAPHY.md).

## Revisar el código

Requiere Apple Silicon, macOS 27, Xcode／SDK y actool compatibles, Deno 2 y Python 3. La compilación usa código local y frameworks de Apple, sin descargar paquetes, usar cuentas ni conectar a la red.


Antes de comprobar o compilar el código, ejecute `python3 scripts/get_fonts.py` para obtener todas las fuentes fijadas. Se verifican los hashes del archivo y de la fuente; un archivo existente distinto se conserva y se rechaza. Revise los derechos antes de redistribuir.

```sh
./grant check-source
./grant public-build
./grant public-check
./grant public-prepare
```

La exportación y la compilación requieren que el índice seleccionado y los archivos de trabajo coincidan con los hashes revisados. Tras revisar y preparar los archivos, ejecuta `python3 scripts/review_source.py --reviewed`, prepara el auxiliar y el archivo de hashes actualizados y ejecuta `./grant public-check`. La compilación usa una copia aislada y no sobrescribe los resultados existentes. Para reemplazar la aplicación, el candidato y la aplicación instalada deben cumplir el mismo requisito designado y certificado hoja exacto; se rechazan las firmas ad hoc. La actualización de hashes conserva los archivos anteriores en `scripts/.grant-review-previous-*` e indica sus nombres. Si se interrumpe, revisa las rutas indicadas y restaura la salida que falte sin sobrescribir otro archivo antes de repetir.

`check-source` revisa fuentes y referencias fijadas, tres idiomas de interfaz, contexto／respuesta puros, política, shell simulado y ajustes aislados. No realiza autorización, sudo real, carga de plugin, inicio de la aplicación ni instalación. `public-build` crea otro candidato sin firma y relee modos y hashes. Omite lanzadores de instalación del sistema y conserva el puntero al candidato firmado. No debes instalarlo ni abrirlo como componente de autenticación aceptado.

Tras preparar archivos por nombre, `public-check`／`public-prepare` leen la selección exacta del índice Git en `public-source.json`. Una salida distinta no se sobrescribe. Historial Git, configuración privada de firma y registros internos quedan fuera. El análisis limitado no certifica todo el historial ni los binarios.

## Firma e instalación

`./grant build` es el flujo firmado separado. Requiere `GRANT_SIGN_IDENTITY` y `GRANT_PLUGIN_SIGN_IDENTITY`, o ambos valores de `Local/signing.json`. Si faltan, falla sin pasar en silencio a una firma distinta. `./grant install-app` instala el candidato del propietario en `~/Applications/Grant.app` y `~/.local/bin/grant`. Abre ajustes con `grant settings` y consulta el estado con `grant status`.

Activar el sistema es otra acción de administrador. Lee antes la [guía de integración y recuperación](docs/INTEGRATION.md). El instalador restaura la política original exacta de Apple, reemplaza el plugin inactivo y la prueba aislada, y solo activa la regla compartida si esa autenticación real tiene éxito. Cancelar o fallar deja la política original; no afirma restaurar la regla anterior de Grant. La recuperación usa el ID del recibo emitido. Una vista previa no demuestra autenticación ni cobertura global.

## sudo del terminal

Es un puente opcional separado: no cambia PAM／sudoers ni añade un daemon. Usa el ajuste `terminalSudo` y `grant_shell.zsh` de la aplicación que hayas instalado. Solo afecta llamadas locales, interactivas y con entrada／salida de terminal. -A／-S／-n explícitos, SUDO_ASKPASS existente, opciones desconocidas, SSH, tmux／screen y scripts mantienen su ruta original; `command sudo` y `/usr/bin/sudo` también la evitan. sudo conserva validación, reintentos, ejecución y caché.

El helper comprueba el padre sudo real, hora de inicio, consola y pipe antes de responder directamente a ese padre. Cancelar envía 0 bytes. Admite 1–255 bytes UTF-8 sin NUL／CR／LF. Borra su búfer mutable, sin prometer borrar cada copia de AppKit. Inicio de sesión, FileVault, Keychain y LocalAuthentication son otras rutas; reintentos y Touch ID requieren aceptación real aparte.

## Datos y licencias

La apariencia se guarda antes de activar en `~/Library/Application Support/Grant/`, y después en `/Library/Application Support/Grant/Preferences/settings.json`. Solo contiene preferencias visuales, nunca contraseñas. El plugin relee cada solicitud; una preferencia inválida no evita la validación de Apple. Compilaciones y pruebas locales quedan en Local, excluido de Git. Los lanzadores instalados necesitan Deno y este checkout; moverlo exige reinstalarlos.

El código y documentos propios usan [MIT](LICENSE). El propietario confirmó el 2026-10-26 que los tres archivos originales de `References/Setup/` son propios y autorizó MIT dentro de Grant, conservando [procedencia y licencia](References/Setup/README.md). No incluye el repositorio Setup, otros archivos, historial ni datos. Los dos iconos SVG originales usan [CC BY 4.0](ARTWORK-LICENSE.md); las fuentes mantienen sus términos. Los candidatos llevan los avisos del software, referencia y arte. Consulta las [dependencias](DEPENDENCIES.md). Se ha autorizado publicar solo el código fuente. Los derechos de los productos con fuentes, la firma, instalación y autorización real del sistema siguen sin verificarse.
