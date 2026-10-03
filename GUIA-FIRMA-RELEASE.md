# Guía: firmar y generar el APK de release (Barbora móvil)

Guía paso a paso, en simple, de los puntos 1 y 2 del empaque. Léela con calma;
está pensada para hacerla **una sola vez**.

---

## ¿Qué es esto y por qué es necesario?

Android **no instala** una app si no está "firmada" digitalmente. La firma es
como la **cédula de identidad de tu app**: garantiza que todas las versiones
(la de hoy y las actualizaciones futuras) vienen del mismo autor (tú).

- En **desarrollo**, Flutter usa una firma "debug" automática (por eso
  `flutter run` funciona sin que hagas nada). Pero esa firma es genérica, la
  tiene todo el mundo, y **no sirve para distribuir** la app de verdad.
- Para **entregar/publicar**, necesitas tu **propia** firma: eso es el
  **keystore** (un archivo `.jks` protegido con contraseña).

### ⚠️ Lo más importante de todo
El **keystore y sus contraseñas son para siempre**. Si actualizas la app en el
futuro, DEBES firmarla con el **mismo** keystore. Si lo **pierdes** (o pierdes
la contraseña):
- No podrás publicar **actualizaciones** de la app (Android las rechaza por
  tener otra firma).
- Tendrías que publicar una app **nueva** (otro paquete) y los usuarios
  perderían la continuidad.

Por eso: **haz respaldo del `.jks` y guarda las contraseñas** en un lugar
seguro (gestor de contraseñas, USB, nube privada). No lo subas al repositorio
(ya está ignorado por git).

---

## ¿Qué es `key.properties`?

Es un archivo de texto que le dice a Gradle (el compilador de Android)
**dónde está tu keystore y cuáles son las contraseñas**, para que firme el APK
automáticamente al compilar. Así no se ponen las contraseñas dentro del código.

- El proyecto **ya está configurado** para leerlo:
  `android/app/build.gradle.kts` busca `android/key.properties`. Si existe,
  firma con tu keystore de release; si no existe, usa la firma debug (para no
  romper `flutter run --release`).
- Este archivo **no se sube** al repo (está en `.gitignore`), porque contiene
  contraseñas.

---

## Paso 1 — Crear el keystore (una sola vez)

Necesitas `keytool`, que viene con el **JDK de Java** (ya lo tienes instalado si
usas Android Studio / Flutter).

1. Abre una terminal en la carpeta `android/app` del proyecto móvil:
   ```
   cd d:\repository\barbora\barbora_movil\android\app
   ```

2. Ejecuta (esto crea el archivo `barbora-release.jks`). `keytool` viene con el
   JDK de Android Studio, que **no está en el PATH**, así que va con la ruta
   completa (verifícala con `flutter doctor -v` → "Java binary at:"; `keytool.exe`
   está en esa misma carpeta `bin`):
   ```
   "C:\Program Files\Android\Android Studio\jbr\bin\keytool" -genkeypair -v -keystore barbora-release.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias barbora
   ```
   - **`-storetype PKCS12`** (no `JKS`): es el formato estándar actual. Así no
     sale el aviso de "formato propietario" que da JKS.

3. Te va a preguntar, en orden:
   - **Contraseña del keystore** (invéntala y anótala) → la escribes dos veces.
   - Nombre, organización, ciudad, país, etc. (puedes poner tu nombre/negocio;
     no es crítico). Al final te pide confirmar con `si`/`yes`.
   - En PKCS12 **la clave usa la misma contraseña del keystore** (no te pedirá
     una aparte). En `key.properties` pondrás esa misma en `keyPassword`.

4. Al terminar tendrás el archivo **`barbora-release.jks`** dentro de
   `android/app/`. **Respáldalo** y guarda la contraseña y el alias (`barbora`).

> El alias `barbora` es el "nombre" de la clave dentro del keystore. Debe
> coincidir con el que pongas en `key.properties`.

> **¿Ya creaste uno con otro nombre (p. ej. `rodex`) por error?** No pasa nada:
> mientras no hayas distribuido una app firmada con él, bórralo y vuelve a
> hacer este paso con `barbora`. (Si ya lo borré yo, simplemente ejecuta el
> comando de arriba.)

---

## Paso 2 — Crear `android/key.properties`

1. Copia la plantilla `android/key.properties.example` a `android/key.properties`
   (mismo directorio `android/`, **no** dentro de `android/app/`).

2. Ábrelo y completa con tus datos reales:
   ```
   storePassword=LA_CONTRASEÑA_DEL_KEYSTORE
   keyPassword=LA_CONTRASEÑA_DEL_KEYSTORE
   keyAlias=barbora
   storeFile=barbora-release.jks
   ```
   - En PKCS12, `keyPassword` y `storePassword` son **la misma**.
   - `storeFile=barbora-release.jks` funciona porque el `.jks` quedó en
     `android/app/`. Si lo guardaste en otro lado, pon la **ruta completa**,
     por ejemplo `storeFile=C:/Users/Eric/llaves/barbora-release.jks` (usa `/`).

3. Guarda. Listo: ya no toques más este archivo.

---

## Paso 3 — Compilar el APK firmado

Desde la carpeta del proyecto móvil (`barbora_movil`):
```
flutter build apk --release
```
- El APK sale en:
  `build/app/outputs/flutter-apk/app-release.apk`
- Ese APK está **firmado con tu keystore** y apunta a **producción**
  (`https://barbora.sczsoft.net`). Es el que instalas en los celulares o
  compartes.

Para **Play Store** (más adelante) se usa un App Bundle:
```
flutter build appbundle --release
```
(sale en `build/app/outputs/bundle/release/app-release.aab`).

---

## Cómo saber que quedó bien firmado

Al compilar, si Gradle encontró tu `key.properties`, usa tu firma de release.
Si no lo encuentra, usa la debug (y verás la app igual, pero **no** sirve para
distribuir). Para confirmar la firma del APK generado, **desde la raíz del proyecto**
(`d:\repository\barbora\barbora_movil`, no desde `android\app`: la ruta del APK es
relativa a la raíz). Los APK actuales usan la firma **v2/v3 de Android**, que
`keytool` no sabe leer (dice "No es un archivo jar firmado"); la herramienta correcta
es `apksigner`, del SDK de Android (`build-tools`):
```
cd d:\repository\barbora\barbora_movil
"C:\Users\Eric\AppData\Local\Android\Sdk\build-tools\37.0.0\apksigner.bat" verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```
Debe mostrar `V2 Signer: certificate DN: CN=<tu nombre>, O=<tu organización>…` (los
datos que pusiste al crear el keystore), no "Android Debug". Si el archivo "no
existe", aún no compilaste: `flutter build apk --release` primero.

---

## Resumen de checklist

- [ ] Crear `barbora-release.jks` con `keytool` en PKCS12 (Paso 1) y **respaldarlo**.
- [ ] Anotar y guardar: contraseña del keystore (en PKCS12 sirve también de
      contraseña de la clave) y el alias (`barbora`).
- [ ] Crear `android/key.properties` desde el `.example` con esos datos (Paso 2).
- [ ] `flutter build apk --release` (Paso 3) → instalar el `app-release.apk`.

> Si algo no queda claro, avísame y lo revisamos juntos cuando lo hagas.
