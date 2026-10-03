import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/admin/data/activity_entry.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';

/// How one activity log line is shown: icon, colour and a sentence such as
/// "Recorded a payment of XAF 50,000".
class ActivityText {
  const ActivityText(this.icon, this.color, this.title);

  final IconData icon;
  final Color color;
  final String title;
}

/// Turns a raw log line into words. [currency] is the property's currency
/// (for amounts); null if the property no longer exists.
ActivityText describeActivity(ActivityEntry entry, {String? currency}) {
  final row = entry.row;
  final before = entry.oldData;
  final after = entry.newData;
  String money(Object? value) {
    final amount = value is int ? value : int.tryParse('$value');
    if (amount == null) return '?';
    return currency == null ? '$amount' : formatMoney(amount, currency);
  }

  String date(Object? value) {
    final parsed = value == null ? null : DateTime.tryParse('$value');
    return parsed == null ? '?' : formatDate(parsed);
  }

  final insert = entry.action == 'INSERT';
  final delete = entry.action == 'DELETE';
  String verb(String added, String edited, String deleted) =>
      insert ? added : (delete ? deleted : edited);

  switch (entry.tableName) {
    case 'payments':
      final kind = row['kind'] == 'balance' ? ' towards a balance' : '';
      final short = row['expected_amount'] != null &&
              (row['amount'] as num) < (row['expected_amount'] as num)
          ? ' (part payment, due ${money(row['expected_amount'])})'
          : '';
      return ActivityText(Icons.payments_rounded, AppColors.paid,
          'Recorded a payment of ${money(row['amount'])}$kind$short');
    case 'payment_voids':
      return ActivityText(Icons.block_rounded, AppColors.overdue,
          'Voided a payment: "${row['reason']}"');
    case 'tenancies':
      if (insert) {
        return ActivityText(Icons.key_rounded, AppColors.primary,
            'Started a tenancy at ${money(row['monthly_rent'])} per month');
      }
      if (before?['status'] == 'active' && after?['status'] == 'ended') {
        return ActivityText(Icons.logout_rounded, AppColors.ended,
            'Ended a tenancy (moved out ${date(after?['end_date'])})');
      }
      if (before?['monthly_rent'] != after?['monthly_rent']) {
        return ActivityText(Icons.trending_up_rounded, AppColors.dueSoon,
            'Changed the rent from ${money(before?['monthly_rent'])} to ${money(after?['monthly_rent'])}');
      }
      if (before?['paid_until'] != after?['paid_until']) {
        return ActivityText(Icons.event_available_rounded, AppColors.paid,
            'Rent now paid until ${date(after?['paid_until'])}');
      }
      return ActivityText(Icons.edit_note_rounded, AppColors.primary,
          '${verb('Added', 'Edited', 'Deleted')} a tenancy');
    case 'tenancy_renewals':
      return ActivityText(Icons.autorenew_rounded, AppColors.primary,
          'Renewed a tenancy until ${date(row['new_end_date'])}');
    case 'apartments':
      return ActivityText(Icons.door_front_door_rounded, AppColors.vacant,
          '${verb('Added', 'Edited', 'Deleted')} apartment ${row['name']}');
    case 'apartment_rents':
      return ActivityText(Icons.savings_rounded, AppColors.vacant,
          'Set an apartment\'s standard rent to ${money(row['monthly_rent'])}');
    case 'properties':
      return ActivityText(Icons.apartment_rounded, AppColors.primary,
          '${verb('Created', 'Edited', 'Deleted')} property ${row['name']}');
    case 'memberships':
      if (insert) {
        return ActivityText(Icons.group_add_rounded, AppColors.accent,
            'Added a team member as ${row['role']}');
      }
      if (delete) {
        return ActivityText(Icons.group_remove_rounded, AppColors.accent,
            'Removed a team member (${row['role']})');
      }
      return ActivityText(Icons.manage_accounts_rounded, AppColors.accent,
          'Changed a team member to ${row['role']}');
    case 'tenants':
      if (!insert && !delete && before?['user_id'] == null && after?['user_id'] != null) {
        return ActivityText(Icons.phone_android_rounded, AppColors.primary,
            '${row['full_name']} joined the app with an invite code');
      }
      if (!insert && !delete && before?['user_id'] != null && after?['user_id'] == null) {
        return ActivityText(Icons.link_off_rounded, AppColors.ended,
            'Disconnected ${row['full_name']}\'s app account');
      }
      return ActivityText(Icons.person_rounded, AppColors.accent,
          '${verb('Added', 'Edited', 'Deleted')} tenant ${row['full_name']}');
    case 'tenant_identities':
      return const ActivityText(Icons.credit_card_rounded, AppColors.accent,
          'Changed a tenant\'s ID card number');
    case 'tenant_invites':
      if (insert) {
        return const ActivityText(Icons.qr_code_2_rounded, AppColors.accent, 'Created an invite code');
      }
      if (after?['cancelled_at'] != null && before?['cancelled_at'] == null) {
        return const ActivityText(Icons.qr_code_2_rounded, AppColors.ended, 'Cancelled an invite code');
      }
      return const ActivityText(Icons.qr_code_2_rounded, AppColors.paid, 'An invite code was used');
    case 'announcements':
      return ActivityText(Icons.campaign_rounded, AppColors.primary,
          'Sent an announcement: "${row['title']}"${row['audience'] == 'all' ? ' to all tenants' : ''}');
    case 'tickets':
      if (insert) {
        return ActivityText(Icons.build_circle_rounded, AppColors.overdue,
            'A tenant reported an issue: "${row['title']}"');
      }
      if (before?['status'] != after?['status']) {
        return ActivityText(Icons.build_circle_rounded, AppColors.dueSoon,
            'Ticket "${row['title']}" is now ${'${after?['status']}'.replaceAll('_', ' ')}');
      }
      return ActivityText(Icons.chat_rounded, AppColors.accent, 'New reply on "${row['title']}"');
    case 'bill_types':
      if (!insert && !delete && before?['enabled'] != after?['enabled']) {
        return ActivityText(Icons.tune_rounded, AppColors.accent,
            '${after?['enabled'] == true ? 'Switched on' : 'Switched off'} ${row['name']} bills');
      }
      return ActivityText(Icons.tune_rounded, AppColors.accent,
          '${verb('Added', 'Edited', 'Deleted')} bill type ${row['name']}');
    case 'bills':
      return ActivityText(Icons.receipt_long_rounded, AppColors.primary,
          'Created bill "${row['title']}" due ${date(row['due_date'])}');
    case 'bill_assignments':
      return ActivityText(Icons.check_circle_rounded, AppColors.paid,
          after?['paid_at'] != null
              ? 'Marked a bill of ${money(row['amount'])} as paid'
              : 'Marked a bill of ${money(row['amount'])} as not paid');
    case 'repairs':
      return ActivityText(Icons.handyman_rounded, AppColors.dueSoon,
          '${insert ? 'Logged' : 'Removed'} repair "${row['title']}"'
          '${insert && row['cost'] != null ? ' costing ${money(row['cost'])}' : ''}');
    case 'receipt_responses':
      return row['response'] == 'confirmed'
          ? const ActivityText(Icons.verified_rounded, AppColors.paid, 'Tenant confirmed a receipt')
          : ActivityText(Icons.report_problem_rounded, AppColors.overdue,
              'Tenant reported a problem with a receipt (${'${row['problem']}'.replaceAll('_', ' ')})');
    case 'auth':
      if (entry.action == 'password_reset') {
        return const ActivityText(Icons.key_rounded, AppColors.dueSoon, 'Reset someone\'s password');
      }
  }
  return ActivityText(Icons.history_rounded, AppColors.ended,
      '${entry.action} on ${entry.tableName}');
}
