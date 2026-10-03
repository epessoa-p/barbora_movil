# Barbora — App del personal

Aplicación móvil para el personal de la barbería: agenda del día, cierre de
atenciones y comisiones propias.

Consume la API de [`barbora_web`](../barbora_web) (`/api/v1`) con Sanctum y la
cabecera `X-Company-Id`. Lo que falta por construir está en [CHECKLIST.md](CHECKLIST.md).

## Arrancar

```bash
flutter pub get

flutter run                 # probar en el emulador o el teléfono
flutter build apk --release # APK para instalar
```

### A qué servidor apunta

Se elige a mano en `lib/core/config.dart`, en el recuadro **SERVIDOR AL QUE
APUNTA LA APP**. Hay dos líneas y solo una debe quedar sin comentar:

| Línea | Servidor | Cuándo |
|---|---|---|
| `_selected = production` | `https://barbora.sczsoft.net` | **Por defecto.** Todo APK que se instale |
| `_selected = development` | `http://10.0.2.2:8070` | Probar contra tu PC con `php artisan serve --port=8070` |

Para cambiar: comenta la activa, descomenta la otra y reinicia la app (hot
restart, no hot reload) o recompila el APK.

`10.0.2.2` es cómo el **emulador** ve el `localhost` del PC. En un teléfono
físico cambia `development` por la IP del PC en la red (por ejemplo
`http://192.168.1.50:8070`) y conecta ambos al mismo wifi.

Para una prueba puntual sin tocar el código, `--dart-define` manda sobre la
línea elegida:

```bash
flutter run --dart-define=BARBORA_API_URL=http://192.168.1.50:8070
```

> Antes de compilar un APK para las barberías, comprueba que la línea activa
> sea `production`: si sale con `development`, la app intentará conectar a tu
> PC y no funcionará en ningún teléfono.

Con el servidor web levantado (`php artisan serve --port=8070` en
`barbora_web`) se puede entrar con cualquiera de las credenciales de
demostración de ese proyecto.

## Cómo está organizado

| Directorio | Qué vive ahí |
|---|---|
| `lib/core/` | Configuración, cliente HTTP, sesión, errores, horas |
| `lib/models/` | Objetos del dominio, con `fromJson` |
| `lib/state/` | Un `ChangeNotifier` por módulo |
| `lib/screens/` | Una pantalla por archivo |
| `lib/widgets/` | Piezas reutilizables |
| `lib/theme/` | Colores, tipografía y estilos |

El estado va con `provider`: `AuthController` decide qué pantalla se ve
(acceso, elegir barbería, la app, o suscripción vencida) y los demás
controladores solo cargan datos.

## Tres decisiones que conviene conocer

**El token va al llavero del sistema**, no a `SharedPreferences`. Da acceso a
los datos del negocio; en preferencias quedaría en texto plano y sería legible
en un móvil con root. Ver `lib/core/session.dart`.

**Las horas se leen con `ShopTime`, no con `DateTime.parse`.** La API manda
`2026-09-26T09:00:00-04:00`, que significa «las nueve en la barbería».
`DateTime.parse` devuelve el instante en UTC y su `.hour` sería 13, así que la
agenda entera aparecería corrida. Es la contraparte de `App\Support\ShopTime`
en el backend, y está cubierto en `test/shop_time_test.dart`.

**El logotipo se compone, no se importa entero.** El `brand.svg` del panel web
lleva la palabra «BARBORA» como elemento `<text>` en Montserrat, y ningún móvil
trae esa fuente: el nombre saldría con otra letra. Se usa `logo.svg`, que es
vector puro, y el nombre se escribe con la Montserrat empaquetada en
`assets/fonts/`. Si cambia la marca, se copian los SVG de
`barbora_web/public/img/` y listo.

## Errores de la API

Los códigos son el contrato con el backend y están traducidos en
`lib/core/api_exception.dart`. Cada uno lleva a un sitio distinto:

| `error` | Qué hace la app |
|---|---|
| `unauthenticated` | Vuelve al inicio de sesión |
| `company_forbidden`, `company_required` | Vuelve a preguntar la barbería |
| `subscription_blocked` | Pantalla de suscripción vencida |
| `plan_required`, `forbidden` | Lo explica, sin ofrecer reintentar |

## Tests

```bash
flutter test
flutter analyze
```

Cubren los modelos frente a respuestas reales de la API, la traducción de cada
código de error, el desfase horario y el recorrido completo de acceso a agenda
contra una API simulada.

### Ver las pantallas sin emulador

```bash
flutter test test/screenshots_test.dart --update-goldens
```

Deja capturas en `test/screenshots/`. El test carga Montserrat a mano porque
`flutter test` no monta fuentes; los iconos sí salen como cuadrados, que es
normal y solo pasa en las capturas.

## Estado

| | |
|---|---|
| Flutter | 3.41.7 (Dart ^3.11.5) |
| Plataformas | Android, iOS |
| Application ID / Bundle ID | `com.barbora.movil` |
