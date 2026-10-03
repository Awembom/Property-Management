import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/core/realtime/live_updates.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';

void main() {
  test('a bill change reloads the bill screens once, not the tickets', () async {
    var billLoads = 0;
    var ticketLoads = 0;
    final container = ProviderContainer(overrides: [
      myBillsProvider.overrideWith((ref, id) async {
        billLoads++;
        return <MyBill>[];
      }),
      tenancyTicketsProvider.overrideWith((ref, id) async {
        ticketLoads++;
        return <Ticket>[];
      }),
    ]);
    addTearDown(container.dispose);
    // Two screens are open: my bills and my issues.
    container.listen(myBillsProvider('t1'), (_, _) {});
    container.listen(tenancyTicketsProvider('t1'), (_, _) {});
    await container.read(myBillsProvider('t1').future);
    await container.read(tenancyTicketsProvider('t1').future);
    expect((billLoads, ticketLoads), (1, 1));

    // The landlord marks the bill paid (and two more rows change at once).
    final live = container.read(liveUpdatesProvider);
    live.tableChanged('bill_assignments', delay: const Duration(milliseconds: 10));
    live.tableChanged('bill_assignments', delay: const Duration(milliseconds: 10));
    live.tableChanged('bills', delay: const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await container.read(myBillsProvider('t1').future);

    expect(billLoads, 2); // reloaded once for the whole burst
    expect(ticketLoads, 1); // untouched
  });

  test('every live table reloads something', () {
    for (final entry in liveUpdateTargets.entries) {
      expect(entry.value, isNotEmpty, reason: entry.key);
    }
  });
}
