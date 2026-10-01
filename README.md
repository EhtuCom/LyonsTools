# Lyons Tools

Utilidades y ajustes para Windows, Office, Java y firma digital, pensadas para despachos de asesores fiscales y abogados en Cataluña. Las mantiene [ehtu.com](https://ehtu.com).

Es un único script de PowerShell con interfaz gráfica, y no hay que instalar nada.

## Cómo abrirlo

Abre **PowerShell** (botón Inicio y escribe `powershell`) y pega:

```powershell
irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1 | iex
```

También puedes descargar [`LyonsTools.cmd`](LyonsTools.cmd) y abrirlo con doble clic.

No hace falta abrir PowerShell como administrador. Lyons Tools se ejecuta con tu usuario y Windows solo pide permiso de administrador en las acciones que lo necesitan (instaladores, certificados raíz y directivas de Office). Así los ajustes se aplican siempre a tu perfil, aunque sea otra cuenta la que acepta el aviso.

## Qué incluye

### Office
| Acción | Qué hace |
|---|---|
| Autoguardado en Word / Excel / PowerPoint cada N minutos | Activa la autorrecuperación con el intervalo elegido. Se aplica como directiva de usuario, así que Office no puede deshacerla al cerrarse. |
| Protección completa contra cierres inesperados | Aplica la autorrecuperación cada N minutos en las tres aplicaciones, conserva la última versión si se cierra sin guardar y activa la copia de seguridad `.wbk` en Word. |
| Buscar documentos recuperables | Localiza archivos `.asd`, `.wbk`, `.xar` y los documentos no guardados de los últimos 30 días. |
| Quitar los ajustes de autoguardado | Devuelve el control a *Archivo > Opciones > Guardar*. |
| Versión de Office, actualizar Office, reparación rápida | Mantenimiento de Office Click-to-Run. |

### Firma digital
| Acción | Qué hace |
|---|---|
| Configurador FNMT | Descarga la última versión desde la sede de la FNMT y la instala. |
| Certificados raíz FNMT | Instala las raíces y las autoridades intermedias de la FNMT. Las raíces solo se instalan si su huella coincide con las raíces oficiales. |
| Certificados raíz del Consorci AOC | Instala la jerarquía de CATCert / Consorci AOC (CA CONSORCI AOC G3, EC-ACC, EC-Ciutadania...), que necesitan el idCAT Certificat, la T-CAT y las webs de la Generalitat y los ayuntamientos. Las raíces también se comprueban por su huella. |
| Mis certificados | Lista los certificados para firmar y avisa de los que caducan en menos de 60 días. |
| Autofirma | Descarga la última versión desde firmaelectronica.gob.es y la instala. |
| Signador AOC | Instala la aplicación nativa del Signador del Consorci AOC y su certificado local. |
| Software de la T-CAT | Instala Bit4id PKI Manager, el controlador de las tarjetas T-CAT emitidas desde el 13/04/2023. |
| Enlaces útiles | FNMT, AEAT, ATC, LexNET, VALIDe, idCAT Mòbil, e-NOTUM y el soporte del Consorci AOC. |

### Java
Comprueba la versión instalada, instala la última versión LTS de Java (Eclipse Temurin) o Java 8 de Oracle, y vacía la caché de Java.

### Windows
Muestra las extensiones de archivo, activa el historial del portapapeles (Win+V) y genera un informe del equipo para soporte. También abre Asistencia rápida, limpia los archivos temporales, vacía la caché DNS, reinicia el Explorador y abre Windows Update.

Todas las descargas salen de las webs oficiales en el momento de usarlas, así que siempre se instala la última versión. Antes de ejecutar un instalador se comprueba su firma digital.

## Uso sin interfaz (despliegue y soporte remoto)

```powershell
# Ver los IDs disponibles
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1))) -List

# Ejecutar acciones concretas
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1))) -Run office-crash-protection,fnmt-root-certs -Minutes 5
```

Los registros se guardan en `%LOCALAPPDATA%\LyonsTools\logs`.

## Desarrollo

```
config/tools.json       Pestañas, secciones y acciones (textos de la interfaz)
functions/<área>/*.ps1  Una función por acción (Verbo-LTNombre)
scripts/start.ps1       Parámetros y estado compartido
scripts/main.ps1        Punto de entrada e interfaz WPF
xaml/MainWindow.xaml    Diseño de la ventana
Compile.ps1             Genera lyonstools.ps1 (un solo archivo)
```

Para añadir una utilidad:
1. Escribe la función en `functions/`.
2. Añade una entrada en `config/tools.json` con `"action": "NombreDeLaFunción"`.
3. Ejecuta `.\Compile.ps1` (o `.\Compile.ps1 -Run` para probarla) y sube el `lyonstools.ps1` generado.

El script generado es solo ASCII: el compilador convierte los acentos. Por eso funciona igual con `irm | iex` que con Windows PowerShell 5.1. En los `.ps1` el texto con acentos tiene que ir entre comillas dobles; el compilador avisa si no es así.

## Licencia

MIT. Lo usas bajo tu responsabilidad.
