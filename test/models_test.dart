import 'package:barbora_movil/models/appointment.dart';
import 'package:barbora_movil/models/commission.dart';
import 'package:barbora_movil/models/company.dart';
import 'package:barbora_movil/models/me.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los `fromJson` frente a respuestas reales de la API.
///
/// Las cargas de ejemplo están copiadas de lo que devuelve /api/v1 de verdad,
/// no inventadas: si el backend cambia una clave, esto falla aquí y no en el
/// teléfono de un barbero a media jornada.
void main() {
  group('Appointment', () {
    final json = {
      'id': 12,
      'starts_at': '2026-09-26T09:00:00-04:00',
      'ends_at': '2026-09-26T09:40:00-04:00',
      'duration_minutes': 40,
      'status': 'confirmada',
      'status_label': 'Confirmada',
      'is_editable': true,
      'notes': null,
      'client': {'id': 3, 'full_name': 'Carlos Mendoza', 'phone': '59171234567'},
      'personal': {'id': 1, 'full_name': 'Iván Céspedes'},
      'branch': 'Centro',
      'services': [
        {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
        {'id': 7, 'name': 'Barba', 'duration_minutes': 10, 'price': 20.0},
      ],
      'total': 70.0,
      'reminded_at': null,
    };

    test('se lee completa', () {
      final a = Appointment.fromJson(json);

      expect(a.id, 12);
      expect(a.client?.fullName, 'Carlos Mendoza');
      expect(a.personal?.fullName, 'Iván Céspedes');
      expect(a.services, hasLength(2));
      expect(a.total, 70.0);
      expect(a.servicesLabel, 'Corte clásico + Barba');
    });

    test('la hora NO se convierte a la del teléfono', () {
      final a = Appointment.fromJson(json);

      // Viene en la zona de la barbería (-04:00) y así se muestra: una cita de
      // las 09:00 es a las 09:00 allí, esté donde esté el barbero.
      expect(a.startsAt.hour, 9);
      expect(a.timeRange, '09:00 – 09:40');
    });

    test('una cita cancelada se marca como liberada', () {
      final a = Appointment.fromJson({...json, 'status': 'cancelada'});

      expect(a.isReleased, isTrue);
      expect(a.isDone, isFalse);
    });

    test('«no se presentó» también libera el hueco', () {
      expect(Appointment.fromJson({...json, 'status': 'no_show'}).isReleased, isTrue);
    });

    test('sin servicios no revienta', () {
      final a = Appointment.fromJson({...json, 'services': <dynamic>[], 'total': null});

      expect(a.services, isEmpty);
      expect(a.servicesLabel, 'Sin servicios');
      expect(a.total, isNull);
    });

    test('sin cliente ni barbero tampoco', () {
      final a = Appointment.fromJson({...json, 'client': null, 'personal': null});

      expect(a.client, isNull);
      expect(a.personal, isNull);
    });
  });

  group('AgendaSummary', () {
    test('la carga se muestra en horas cuando pasa de 60 minutos', () {
      expect(const AgendaSummary(minutes: 45).workloadLabel, '45 min');
      expect(const AgendaSummary(minutes: 120).workloadLabel, '2h');
      expect(const AgendaSummary(minutes: 265).workloadLabel, '4h 25min');
    });
  });

  group('Me', () {
    final json = {
      'user': {
        'id': 4,
        'name': 'Tania Molina',
        'email': 'tania.molina@barberiademo.test',
        'phone': null,
        'is_super_admin': false,
      },
      'company': {
        'id': 1,
        'name': 'Barbería Demo',
        'currency': 'BOB',
        'currency_symbol': 'Bs',
        'timezone': 'America/La_Paz',
        'country': 'BO',
      },
      'personal': {
        'id': 3,
        'full_name': 'Tania Molina',
        'cargo': 'Barbero',
        'bookable': true,
        'photo_url': null,
        'agenda_color': '#E64A38',
      },
      'role': {'slug': 'barber', 'name': 'Barbero'},
      'permissions': ['appointments.view', 'appointments.edit', 'commissions.view'],
      'plan': {
        'name': 'Premium',
        'modules': ['agenda', 'pos', 'comisiones'],
        'module_labels': {'agenda': 'Agenda / Citas'},
      },
      'subscription': {
        'status': 'active',
        'on_trial': false,
        'allows_write': true,
        'trial_ends_at': null,
        'current_period_end': '2026-10-22T00:00:00-04:00',
      },
    };

    test('se lee completo', () {
      final me = Me.fromJson(json);

      expect(me.user.name, 'Tania Molina');
      expect(me.company?.symbol, 'Bs');
      expect(me.personal?.cargo, 'Barbero');
      expect(me.role?.slug, 'barber');
      expect(me.planName, 'Premium');
      expect(me.subscription?.allowsWrite, isTrue);
    });

    test('los permisos deciden qué se puede hacer', () {
      final me = Me.fromJson(json);

      expect(me.can('appointments.edit'), isTrue);
      expect(me.can('sales.create'), isFalse);
    });

    test('el superadmin lo puede todo con el comodín', () {
      final me = Me.fromJson({...json, 'permissions': ['*']});

      expect(me.can('cualquier.cosa'), isTrue);
    });

    test('los módulos del plan ocultan pantallas', () {
      final me = Me.fromJson(json);

      expect(me.hasModule('comisiones'), isTrue);
      expect(me.hasModule('inventario'), isFalse);
    });

    test('un administrador sin ficha de personal se detecta', () {
      final me = Me.fromJson({...json, 'personal': null});

      expect(me.hasStaffProfile, isFalse);
      expect(me.personal, isNull);
    });

    test('sin empresa activa el resto sigue leyéndose', () {
      final me = Me.fromJson({
        ...json,
        'company': null,
        'personal': null,
        'role': null,
        'plan': null,
        'subscription': null,
        'permissions': <dynamic>[],
      });

      expect(me.company, isNull);
      expect(me.permissions, isEmpty);
      expect(me.planModules, isEmpty);
      expect(me.user.name, 'Tania Molina');
    });

    test('las iniciales salen del nombre del personal', () {
      expect(Me.fromJson(json).personal!.initials, 'TM');
    });
  });

  group('Company en el comprobante', () {
    test('arma la línea fiscal con la etiqueta del país', () {
      final c = Company.fromJson({
        'id': 1,
        'name': 'Barbería Demo',
        'tax_id': '1023456789',
        'tax_id_label': 'NIT',
      });

      expect(c.taxLine, 'NIT: 1023456789');
    });

    test('en Perú la etiqueta es RUC, no NIT', () {
      final c = Company.fromJson({'id': 2, 'name': 'Lima', 'tax_id': '20123', 'tax_id_label': 'RUC'});

      expect(c.taxLine, 'RUC: 20123');
    });

    test('sin número fiscal no hay línea', () {
      expect(Company.fromJson({'id': 1, 'name': 'X'}).taxLine, isNull);
    });

    test('sin pie propio se agradece la visita', () {
      expect(Company.fromJson({'id': 1, 'name': 'X'}).footer, '¡Gracias por tu visita!');
      expect(
        Company.fromJson({'id': 1, 'name': 'X', 'receipt_footer': 'Síguenos en @demo'}).footer,
        'Síguenos en @demo',
      );
    });
  });

  group('CommissionReport', () {
    final json = {
      'period': {'from': '2026-09-01', 'to': '2026-09-30', 'label': '01/09/2026 – 30/09/2026'},
      'totals': {
        'earned': 29.5,
        'pending': 29.5,
        'settled': 0.0,
        'tips': 10.0,
        'currency': 'BOB',
        'currency_symbol': 'Bs',
      },
      'data': [
        {
          'id': 1,
          'earned_at': '2026-09-22T10:30:00-04:00',
          'description': 'Corte clásico',
          'base_amount': 50.0,
          'rate_label': '15%',
          'amount': 7.5,
          'settled': false,
        },
      ],
    };

    test('se lee y suma lo que hay que cobrar', () {
      final r = CommissionReport.fromJson(json);

      expect(r.earned, 29.5);
      expect(r.pending, 29.5);
      expect(r.tips, 10.0);
      // Lo que el barbero se lleva: lo pendiente más las propinas.
      expect(r.totalToCollect, 39.5);
      expect(r.currencySymbol, 'Bs');
      expect(r.entries, hasLength(1));
    });

    test('un importe redondo llega como decimal, no como entero', () {
      // La API usa JSON_PRESERVE_ZERO_FRACTION justo para esto: si mandara un
      // entero, el «as double» de Dart reventaría.
      final r = CommissionReport.fromJson({
        ...json,
        'totals': <String, dynamic>{
          ...(json['totals']! as Map<String, dynamic>),
          'earned': 30.0,
        },
      });

      expect(r.earned, 30.0);
    });

    test('sin comisiones el periodo se sigue leyendo', () {
      final r = CommissionReport.fromJson({...json, 'data': <dynamic>[]});

      expect(r.entries, isEmpty);
      expect(r.periodLabel, isNotEmpty);
    });
  });

  group('WorkSlot', () {
    test('se lee y arma el rango', () {
      final s = WorkSlot.fromJson({
        'id': 2,
        'weekday': 3,
        'weekday_label': 'Miércoles',
        'start_time': '09:00',
        'end_time': '13:00',
        'branch': null,
      });

      expect(s.weekday, 3);
      expect(s.range, '09:00 – 13:00');
      expect(s.branch, isNull);
    });
  });
}

