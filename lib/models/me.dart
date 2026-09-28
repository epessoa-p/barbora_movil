import '../core/shop_time.dart';
import 'cash.dart';
import 'company.dart';

/// Respuesta de `GET /me`: todo lo que la app necesita para arrancar.
class Me {
  const Me({
    required this.user,
    this.company,
    this.personal,
    this.role,
    this.permissions = const [],
    this.planModules = const [],
    this.planName,
    this.subscription,
    this.paymentMethods = const [],
  });

  final AppUser user;
  final Company? company;
  final StaffProfile? personal;
  final UserRole? role;

  /// Permisos dentro de la barbería activa. `['*']` para el superadmin.
  final List<String> permissions;

  /// Módulos que incluye el plan contratado: agenda, pos, caja…
  final List<String> planModules;
  final String? planName;

  final SubscriptionStatus? subscription;

  /// Con qué puede cobrar esta barbería. Los define ella, no la app.
  final List<PaymentMethod> paymentMethods;

  /// Los que de verdad entran al cajón, para el arqueo.
  List<PaymentMethod> get cashMethods =>
      paymentMethods.where((m) => m.countsAsCash).toList();

  bool can(String permission) =>
      permissions.contains('*') || permissions.contains(permission);

  /// ¿El plan de la barbería incluye este módulo? La app oculta lo que no.
  bool hasModule(String module) => planModules.contains(module);

  /// Solo quien tiene ficha de personal puede usar las pantallas «lo mío».
  bool get hasStaffProfile => personal != null;

  factory Me.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] as Map<String, dynamic>?;

    return Me(
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      company: json['company'] == null
          ? null
          : Company.fromJson(json['company'] as Map<String, dynamic>),
      personal: json['personal'] == null
          ? null
          : StaffProfile.fromJson(json['personal'] as Map<String, dynamic>),
      role: json['role'] == null
          ? null
          : UserRole.fromJson(json['role'] as Map<String, dynamic>),
      permissions: (json['permissions'] as List?)?.map((e) => '$e').toList() ?? const [],
      planModules: (plan?['modules'] as List?)?.map((e) => '$e').toList() ?? const [],
      planName: plan?['name'] as String?,
      subscription: json['subscription'] == null
          ? null
          : SubscriptionStatus.fromJson(json['subscription'] as Map<String, dynamic>),
      paymentMethods: (json['payment_methods'] as List?)
              ?.map((e) => PaymentMethod.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.isSuperAdmin = false,
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final bool isSuperAdmin;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        isSuperAdmin: json['is_super_admin'] as bool? ?? false,
      );
}

/// La ficha de personal del usuario dentro de la barbería.
/// Es null para quien tiene cuenta pero no atiende: un administrador, por ejemplo.
class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.fullName,
    this.cargo,
    this.bookable = false,
    this.photoUrl,
    this.agendaColor,
  });

  final int id;
  final String fullName;
  final String? cargo;
  final bool bookable;
  final String? photoUrl;
  final String? agendaColor;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters(2);
    return '${parts.first.characters(1)}${parts.elementAt(1).characters(1)}';
  }

  factory StaffProfile.fromJson(Map<String, dynamic> json) => StaffProfile(
        id: json['id'] as int,
        fullName: json['full_name'] as String? ?? '',
        cargo: json['cargo'] as String?,
        bookable: json['bookable'] as bool? ?? false,
        photoUrl: json['photo_url'] as String?,
        agendaColor: json['agenda_color'] as String?,
      );
}

extension on String {
  String characters(int n) => length <= n ? toUpperCase() : substring(0, n).toUpperCase();
}

class UserRole {
  const UserRole({required this.slug, required this.name});

  final String slug;
  final String name;

  factory UserRole.fromJson(Map<String, dynamic> json) => UserRole(
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

class SubscriptionStatus {
  const SubscriptionStatus({
    required this.status,
    this.onTrial = false,
    this.allowsWrite = true,
    this.trialEndsAt,
    this.currentPeriodEnd,
  });

  final String status;
  final bool onTrial;
  final bool allowsWrite;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) => SubscriptionStatus(
        status: json['status'] as String? ?? '',
        onTrial: json['on_trial'] as bool? ?? false,
        allowsWrite: json['allows_write'] as bool? ?? true,
        trialEndsAt: ShopTime.tryParse(json['trial_ends_at'] as String?),
        currentPeriodEnd: ShopTime.tryParse(json['current_period_end'] as String?),
      );
}
