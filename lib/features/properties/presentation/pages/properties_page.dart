import 'package:flutter/material.dart';

class PropertiesPage extends StatelessWidget {
  const PropertiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final properties = [
      'Sunset Apartments',
      'Harbor Heights',
      'Maple Residences',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Properties')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: properties.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final property = properties[index];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.apartment_rounded)),
              title: Text(property),
              subtitle: const Text('3 apartments • 2 active tenancies'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {},
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: 'Add property',
        child: const Icon(Icons.add),
      ),
    );
  }
}
