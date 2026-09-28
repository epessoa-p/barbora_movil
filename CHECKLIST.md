# Barbora móvil — checklist

App del **personal** de la barbería (no de clientes finales). Consume
`/api/v1` de [`barbora_web`](../barbora_web); el contrato está documentado en
su README, sección «API móvil».

> Al cerrar algo, márcalo aquí. Lo que quede en `[ ]` es lo que falta.

---

## Cómo se añade una pantalla

1. **Modelo** en `lib/models/` con `fromJson`. Nada de `Map` sueltos por la app.
2. **Llamada** en `lib/core/api_client.dart` o en el controlador del módulo.
3. **Estado** en `lib/state/` (un `ChangeNotifier` por módulo).
4. **Pantalla** en `lib/screens/`, que solo lee del estado y pinta.
5. Los errores **no se capturan en la pantalla**: los traduce `ApiException`
   y los muestra `widgets/error_view.dart`.
6. Una captura nueva en `test/screenshots_test.dart`, para poder mirarla.

### Mapa de directorios

| Directorio | Qué vive ahí |
|---|---|
| `lib/core/` | Configuración, cliente HTTP, sesión, errores, horas |
| `lib/models/` | Objetos del dominio, con `fromJson` |
| `lib/state/` | `ChangeNotifier` por módulo |
| `lib/screens/` | Una pantalla por archivo |
| `lib/widgets/` | Piezas reutilizables |
| `lib/theme/` | Colores, tipografía y estilos |
| `assets/img/` | Logo, copiado de `barbora_web/public/img/` |
| `assets/fonts/` | Montserrat, la tipografía del logotipo |

### Dos cosas que no son obvias

- **`ShopTime`, no `DateTime.parse`.** La API manda las horas con el desfase
  de la barbería. `DateTime.parse` devuelve el instante en UTC, así que una
  cita de las 09:00 se vería a las 13:00. Ver `lib/core/shop_time.dart`.
- **El logotipo se compone, no se importa entero.** `brand.svg` lleva la
  palabra «BARBORA» como `<text>` en Montserrat, y ningún móvil trae esa
  fuente. Se usa `logo.svg` (vector puro) y el nombre se escribe con la
  Montserrat empaquetada. Ver `lib/widgets/brand_logo.dart`.

---

## Base

- [x] Dependencias: `http`, `flutter_secure_storage`, `provider`, `intl`, `flutter_svg`
- [x] Configuración de la URL de la API por `--dart-define`
- [x] Cliente HTTP con `Authorization: Bearer` y `X-Company-Id`
- [x] `ApiException`: traduce los códigos de error de la API a algo mostrable
- [x] Sesión persistente: token en almacenamiento seguro, no en preferencias
- [x] Tema visual con los colores del logo (negro grafito y rojo cobre)
- [x] Localización en español (fechas y textos del sistema)

## Acceso

- [x] Pantalla de inicio de sesión
- [x] Elegir barbería cuando el usuario pertenece a más de una
- [x] Arranque: si hay token guardado, entrar directo
- [x] Cerrar sesión, con confirmación
- [x] Al recibir 401, volver al inicio de sesión
- [x] Pantalla de suscripción vencida (402), con reintento
- [ ] Recuperar contraseña (falta también en el backend)

## Agenda

- [x] Agenda del día, con navegación entre días y salto a hoy
- [x] Selector de fecha
- [x] Ver el detalle de una cita
- [x] Marcar atendida / no se presentó / cancelada / confirmada
- [x] Motivo al cancelar
- [x] Mostrar los bloqueos del día (vacaciones, feriados)
- [x] «Mi agenda» frente a la agenda completa de la barbería
- [x] Resumen del día: citas, pendientes, atendidas y tiempo ocupado
- [ ] Filtrar por barbero dentro de la agenda de la barbería
- [ ] Vista de semana

## Lo mío

- [x] Mi horario de trabajo, con los días libres a la vista
- [x] Mis comisiones del periodo, con lo pendiente de cobro
- [x] Elegir el periodo (semana, este mes, mes pasado)

## Caja y cobro

- [x] Turno de caja: abrir con fondo, ver el efectivo esperado y arquear
- [x] Movimientos manuales (entra / sale), con método de pago
- [x] Lista de movimientos del turno
- [x] Cobrar: comanda de servicios, descuento, propina y pago repartido
- [x] **Clave de idempotencia por comanda.** Se genera una vez y se reutiliza en
      cada reintento: si el cobro se pierde por red y el barbero lo repite, el
      servidor devuelve la venta original en lugar de cobrar dos veces.
      Ver `lib/state/checkout_controller.dart`.
- [x] **Cobrar una cita desde su detalle.** Arranca la comanda con el cliente,
      el barbero y los servicios al precio que se pactó al reservar; al cobrar,
      el servidor marca la cita como atendida.
- [x] **Productos en la comanda**, con el stock a la vista. No deja añadir más
      de lo que queda: el servidor lo rechazaría igual, pero es mejor avisar
      antes de prometérselo al cliente.
- [x] **Comprobante** al terminar el cobro, y copiable como texto para mandarlo
      por WhatsApp (que es lo que se hace de verdad; nadie lleva impresora).
- [ ] Descuento y propina desde la pantalla (el controlador ya los soporta)
- [ ] Elegir el cliente al cobrar una venta suelta

## Catálogo

- [x] Lista de servicios y de productos (dentro de la pantalla de cobro)
- [ ] Pantalla propia de servicios
- [ ] Buscar clientes *(la API ya la expone: `GET /clients?q=`)*
- [ ] Ficha del cliente

## Pendiente de API

Lo que la app necesitará y el backend todavía no expone:

- [ ] Crear y reprogramar citas desde el móvil
- [ ] Notificaciones push cuando entra una cita

## Calidad

- [x] Tests de los modelos (`fromJson`) con cargas reales de la API
- [x] Tests de `ApiException` (cada código de error)
- [x] Tests de `ShopTime` (el desfase horario)
- [x] Tests de recorrido: acceso → barbería → agenda, contra una API simulada
- [x] `flutter analyze` sin avisos
- [x] Capturas de todas las pantallas (`flutter test test/screenshots_test.dart --update-goldens`)
- [ ] Probar en un dispositivo físico contra el servidor real

## Publicación

- [ ] Icono de la app e imagen de arranque con la marca
- [ ] Firma de Android (`keystore`) y perfil de iOS
- [x] El APK release apunta a producción (`https://barbora.sczsoft.net`); en
      desarrollo, al servidor local. `--dart-define=BARBORA_API_URL=...` manda
      sobre ambos. Ninguna credencial del servidor va dentro de la app.
- [x] Permiso de Internet en el manifiesto principal (Flutter solo lo pone en
      los de depuración: sin él, el APK instalado no conecta a nada)
- [ ] Desplegar Barbora en `barbora.sczsoft.net`: hoy ese subdominio sirve la
      web corporativa de SCZ SOFT y la API responde 404
