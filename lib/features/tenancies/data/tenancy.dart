import 'package:rental_app/features/tenancies/data/rent_status.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';
import 'package:rental_app/shared/utils/dates.dart';

/// A tenancy WITHOUT money figures: one row of the `tenancy_overview` view.
///
/// Every staff member (caretakers included) can read this, which is why it's
/// what lists and status badges use. Rent amounts live in [TenancyMoney].
class TenancyOverview {
  const TenancyOverview({
    required this.id,
    required this.propertyId,
    required this.apartmentId,
    required this.apartmentName,
    required this.tenantId,
    required this.tenantName,
    required this.paymentIntervalMonths,
    required this.startDate,
    required this.billingStartDate,
    required this.paidUntil,
    required this.paidMonths,
    required this.isActive,
    this.endDate,
    this.rentStatus,
    this.agreementAcceptedAt,
    this.agreementText,
    this.remindersPausedUntil,
    this.tenantHasAccount = false,
  });

  final String id;
  final String propertyId;
  final String apartmentId;
  final String apartmentName;
  final String tenantId;
  final String tenantName;
  /// How often they pay, in months (1, 3, 6, 12 or custom). See PaymentInterval.
  final int paymentIntervalMonths;

  /// Move-in date.
  final DateTime startDate;

  /// Rent is counted from this date (usually the move-in date).
  final DateTime billingStartDate;

  /// Months covered by (non-voided) rent payments so far.
  final int paidMonths;

  /// Planned lease end while active; the move-out date once ended.
  final DateTime? endDate;

  /// The next due date: the first day NOT covered by rent.
  final DateTime paidUntil;

  final bool isActive;

  /// Only set for active tenancies.
  final RentStatus? rentStatus;

  /// When the tenant accepted the tenancy agreement in the app (null = not yet).
  final DateTime? agreementAcceptedAt;

  /// The owner's agreement text for this unit or property (null = the app's
  /// default). May contain placeholders like {tenant}; see agreement_text.dart.
  final String? agreementText;

  /// Automatic rent reminders are paused until this day (null = on).
  final DateTime? remindersPausedUntil;

  /// The tenant joined the app (so they can get notifications).
  final bool tenantHasAccount;

  /// Reminders are paused right now.
  bool get remindersPaused => remindersPausedUntil != null && daysUntil(remindersPausedUntil!) >= 0;

  /// The date rent will be paid up to after a payment of [months] months.
  ///
  /// Counted from the billing start like the database does (record_payment),
  /// so the screen shows exactly the date the payment will produce.
  DateTime paidUntilAfter(int months) => addMonths(billingStartDate, paidMonths + months);

  /// True if the lease end date has passed but the tenant is still there.
  bool get leaseExpired =>
      isActive && endDate != null && daysUntil(endDate!) < 0;

  /// Columns to select from `tenancy_overview` for [TenancyOverview.fromJson].
  static const columns =
      'id, property_id, apartment_id, apartment_name, tenant_id, '
      'tenant_name, payment_interval_months, start_date, end_date, billing_start_date, '
      'paid_until, paid_months, status, rent_status, agreement_accepted_at, agreement_text, '
      'reminders_muted_until, tenant_has_account';

  factory TenancyOverview.fromJson(Map<String, dynamic> json) {
    final status = json['rent_status'] as String?;
    return TenancyOverview(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      apartmentId: json['apartment_id'] as String,
      apartmentName: json['apartment_name'] as String,
      tenantId: json['tenant_id'] as String,
      tenantName: json['tenant_name'] as String,
      paymentIntervalMonths: json['payment_interval_months'] as int,
      startDate: parseDbDate(json['start_date'] as String),
      endDate: parseDbDateOrNull(json['end_date'] as String?),
      billingStartDate: parseDbDate(json['billing_start_date'] as String),
      paidUntil: parseDbDate(json['paid_until'] as String),
      paidMonths: json['paid_months'] as int,
      isActive: json['status'] == 'active',
      rentStatus: status == null ? null : RentStatus.fromJson(status),
      agreementAcceptedAt: json['agreement_accepted_at'] == null
          ? null
          : DateTime.parse(json['agreement_accepted_at'] as String).toLocal(),
      agreementText: json['agreement_text'] as String?,
      remindersPausedUntil: parseDbDateOrNull(json['reminders_muted_until'] as String?),
      tenantHasAccount: json['tenant_has_account'] as bool? ?? false,
    );
  }
}

/// The money side of a tenancy. Only owners, managers (and the tenant) can
/// read it; the database returns nothing to caretakers (CLAUDE.md, rule 5).
class TenancyMoney {
  const TenancyMoney({
    required this.monthlyRent,
    this.notes,
    this.standardMonthlyRent,
    this.balance = 0,
    this.renewals = const [],
  });

  /// Rent per month, in the currency's smallest unit.
  final int monthlyRent;

  final String? notes;

  /// The apartment's standard monthly rent (from `apartment_rents`), to show
  /// when this tenant's rent was negotiated differently. null if not set.
  final int? standardMonthlyRent;

  /// Money still owed (from part payments). Negative = paid in advance.
  final int balance;

  /// Lease renewals, newest first.
  final List<TenancyRenewal> renewals;

  static const columns = 'monthly_rent, notes';

  /// True if this tenant's rent differs from the apartment's standard rent.
  bool get differsFromStandard =>
      standardMonthlyRent != null && monthlyRent != standardMonthlyRent;
}

/// One renewal of a tenancy (`tenancy_renewals`): the lease end and rent
/// before and after.
class TenancyRenewal {
  const TenancyRenewal({
    required this.createdAt,
    required this.newEndDate,
    required this.oldMonthlyRent,
    required this.newMonthlyRent,
    this.oldEndDate,
    this.notes,
  });

  final DateTime createdAt;
  final DateTime? oldEndDate;
  final DateTime newEndDate;
  final int oldMonthlyRent;
  final int newMonthlyRent;
  final String? notes;

  static const columns =
      'created_at, old_end_date, new_end_date, old_monthly_rent, new_monthly_rent, notes';

  factory TenancyRenewal.fromJson(Map<String, dynamic> json) {
    return TenancyRenewal(
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      oldEndDate: parseDbDateOrNull(json['old_end_date'] as String?),
      newEndDate: parseDbDate(json['new_end_date'] as String),
      oldMonthlyRent: json['old_monthly_rent'] as int,
      newMonthlyRent: json['new_monthly_rent'] as int,
      notes: json['notes'] as String?,
    );
  }
}

/// Everything the tenancy screen shows.
class TenancyDetails {
  const TenancyDetails({
    required this.overview,
    required this.tenant,
    this.money,
  });

  final TenancyOverview overview;
  final Tenant tenant;

  /// null for caretakers.
  final TenancyMoney? money;
}

/// What staff fill in to start a tenancy (see start_tenancy() in the database).
class NewTenancy {
  const NewTenancy({
    required this.apartmentId,
    required this.monthlyRent,
    required this.paymentIntervalMonths,
    required this.startDate,
    this.existingTenantId,
    this.tenantName,
    this.tenantPhone,
    this.tenantEmail,
    this.tenantIdNumber,
    this.endDate,
    this.paidUntil,
    this.notes,
  });

  final String apartmentId;
  final int monthlyRent;
  final int paymentIntervalMonths;
  final DateTime startDate;

  /// Either an existing contact...
  final String? existingTenantId;

  /// ...or a new one.
  final String? tenantName;
  final String? tenantPhone;
  final String? tenantEmail;

  /// ID card number (only stored for new tenants; owners/managers see it).
  final String? tenantIdNumber;

  final DateTime? endDate;

  /// Set when the tenant already paid up to this date before using the app.
  final DateTime? paidUntil;
  final String? notes;

  Map<String, dynamic> toRpcParams() {
    return {
      'p_apartment_id': apartmentId,
      'p_monthly_rent': monthlyRent,
      'p_payment_interval_months': paymentIntervalMonths,
      'p_start_date': toDbDate(startDate),
      'p_tenant_id': existingTenantId,
      'p_tenant_name': tenantName,
      'p_tenant_phone': tenantPhone,
      'p_tenant_email': tenantEmail,
      'p_tenant_id_number': tenantIdNumber,
      'p_end_date': endDate == null ? null : toDbDate(endDate!),
      'p_billing_start_date': paidUntil == null ? null : toDbDate(paidUntil!),
      'p_notes': notes,
    };
  }
}
