import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phone's simple settings store. Set in main.dart; null in tests (then
/// the onboarding counts as seen).
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

/// Has this phone seen the onboarding? It shows once, before the welcome
/// screen, and can be skipped.
class OnboardingSeenNotifier extends Notifier<bool> {
  static const _key = 'onboarding_seen';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs == null || (prefs.getBool(_key) ?? false);
  }

  Future<void> markSeen() async {
    state = true;
    await ref.read(sharedPreferencesProvider)?.setBool(_key, true);
  }
}

final onboardingSeenProvider = NotifierProvider<OnboardingSeenNotifier, bool>(OnboardingSeenNotifier.new);

/// One slide: a big picture made of icons, a title and a sentence.
class _Slide {
  const _Slide(this.color, this.icon, this.extras, this.title, this.text);

  final Color color;
  final IconData icon;
  final List<IconData> extras;
  final String title;
  final String text;
}

const _slides = [
  _Slide(
    AppColors.primary,
    Icons.home_rounded,
    [Icons.receipt_long_rounded, Icons.payments_rounded, Icons.campaign_rounded],
    'Welcome to Homedly',
    'Rent, receipts, bills and messages between landlords and tenants, in one simple app.',
  ),
  _Slide(
    AppColors.accent,
    Icons.apartment_rounded,
    [Icons.payments_rounded, Icons.notifications_active_rounded, Icons.groups_rounded],
    'For landlords',
    'See every unit at a glance, record rent, send bills and reminders, and know who is late.',
  ),
  _Slide(
    AppColors.paid,
    Icons.event_available_rounded,
    [Icons.receipt_rounded, Icons.build_circle_rounded, Icons.call_rounded],
    'For tenants',
    'Know when rent is due, check your receipts, see your bills and report anything that needs fixing.',
  ),
  _Slide(
    AppColors.dueSoon,
    Icons.verified_user_rounded,
    [Icons.qr_code_2_rounded, Icons.cloud_off_rounded, Icons.lock_rounded],
    'Safe and always with you',
    'Receipts can\'t be faked, your information stays private, and the app works even without internet.',
  ),
];

/// Swipe through [_slides]; "Skip" or "Get started" go to the welcome screen.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(onboardingSeenProvider.notifier).markSeen();
    if (mounted) context.go(AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    final color = _slides[_page].color;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(onPressed: last ? null : _finish, child: const Text('Skip')),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => _SlideView(slide: _slides[index]),
              ),
            ),
            // Dots: where am I?
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? color : AppColors.muted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: last
                      ? _finish
                      : () => _controller.nextPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          ),
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Picture(slide: slide),
          const SizedBox(height: 40),
          Text(slide.title, textAlign: TextAlign.center, style: text.headlineSmall),
          const SizedBox(height: 12),
          Text(
            slide.text,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// A big gradient circle with the main icon, and small icons around it.
class _Picture extends StatelessWidget {
  const _Picture({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    const size = 240.0;
    final positions = [const Alignment(-1, -0.55), const Alignment(1, -0.75), const Alignment(0.9, 0.85)];
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Center(
            child: Container(
              width: size * 0.72,
              height: size * 0.72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.gradientFor(slide.color),
                boxShadow: [
                  BoxShadow(color: slide.color.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 12)),
                ],
              ),
              child: Icon(slide.icon, color: Colors.white, size: 84),
            ),
          ),
          for (var i = 0; i < slide.extras.length; i++)
            Align(
              alignment: positions[i],
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: AppColors.cardShadow(context),
                ),
                child: Icon(slide.extras[i], color: slide.color, size: 28),
              ),
            ),
        ],
      ),
    );
  }
}
