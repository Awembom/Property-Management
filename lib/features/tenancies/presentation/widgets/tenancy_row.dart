import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/presentation/widgets/rent_status_pill.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/user_avatar.dart';

/// One tenancy as a row: avatar, tenant, unit and property, rent status.
/// Used on Home ("Needs attention") and in the Tenants tab.
class TenancyRow extends StatelessWidget {
  const TenancyRow({super.key, required this.tenancy, required this.propertyName});

  final TenancyOverview tenancy;
  final String propertyName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push(AppRoutes.tenancyDetail(tenancy.propertyId, tenancy.id)),
      child: Row(
        children: [
          UserAvatar(name: tenancy.tenantName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tenancy.tenantName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                Text(
                  'Unit ${tenancy.apartmentName} · $propertyName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
                Text(
                  rentDueText(tenancy),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: tenancyColor(tenancy)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RentStatusPill(tenancy: tenancy),
        ],
      ),
    );
  }
}

