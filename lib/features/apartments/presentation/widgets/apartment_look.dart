import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';

/// How an apartment is shown: its colour, label and icon.
///   Vacant -> blue.  Occupied -> the rent status colour (green/amber/red).
({Color color, String label, IconData icon}) apartmentLook(
  ApartmentWithTenancy item,
) {
  final tenancy = item.activeTenancy;
  if (tenancy == null) {
    return (
      color: AppColors.vacant,
      label: 'Vacant',
      icon: Icons.meeting_room_outlined,
    );
  }
  final status = tenancy.rentStatus;
  if (status == null) {
    return (
      color: AppColors.paid,
      label: 'Occupied',
      icon: Icons.person_rounded,
    );
  }
  return (color: status.color, label: status.label, icon: status.icon);
}
