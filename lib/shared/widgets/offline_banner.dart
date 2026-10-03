import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/connection_status.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/offline/outbox.dart';

/// A slim grey "Offline" strip above every screen while there's no
/// connection. Tapping it says when the saved data was last updated and
/// how many things are waiting to be sent. Wraps the whole app
/// (MaterialApp.builder in main.dart).
class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  bool _showDetails = false;
  DateTime? _lastUpdated;

  Future<void> _toggle() async {
    if (!_showDetails) {
      _lastUpdated = await ref.read(offlineCacheProvider).lastUpdated();
    }
    if (mounted) setState(() => _showDetails = !_showDetails);
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(connectionProvider.select((c) => c.online));
    if (online) {
      _showDetails = false;
      return widget.child;
    }
    final waiting = ref.watch(outboxProvider).value?.length ?? 0;
    final top = MediaQuery.paddingOf(context).top;

    return Column(
      children: [
        Material(
          color: const Color(0xFF5A5652),
          child: InkWell(
            onTap: _toggle,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, top + 3, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 13, color: Colors.white70),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _showDetails ? offlineDetails(_lastUpdated, waiting) : 'Offline',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The screens below no longer need to avoid the status bar.
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child)),
      ],
    );
  }
}

/// "Offline · last updated 2 h ago · 1 waiting to send".
String offlineDetails(DateTime? lastUpdated, int waiting, {DateTime? now}) {
  final parts = ['Offline'];
  if (lastUpdated != null) {
    final age = (now ?? DateTime.now()).difference(lastUpdated);
    final ago = age.inMinutes < 1
        ? 'just now'
        : age.inHours < 1
            ? '${age.inMinutes} min ago'
            : age.inDays < 1
                ? '${age.inHours} h ago'
                : age.inDays == 1
                    ? '1 day ago'
                    : '${age.inDays} days ago';
    parts.add('last updated $ago');
  }
  if (waiting > 0) parts.add('$waiting waiting to send');
  return parts.join(' · ');
}
