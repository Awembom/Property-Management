import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/admin/presentation/pages/admin_page.dart';
import 'package:rental_app/features/announcements/presentation/pages/announcements_page.dart';
import 'package:rental_app/features/announcements/presentation/pages/my_announcements_page.dart';
import 'package:rental_app/features/announcements/presentation/pages/new_announcement_page.dart';
import 'package:rental_app/features/bills/presentation/pages/bill_page.dart';
import 'package:rental_app/features/bills/presentation/pages/bill_types_page.dart';
import 'package:rental_app/features/bills/presentation/pages/bills_page.dart';
import 'package:rental_app/features/bills/presentation/pages/new_bill_page.dart';
import 'package:rental_app/features/tickets/presentation/pages/new_ticket_page.dart';
import 'package:rental_app/features/tickets/presentation/pages/property_tickets_page.dart';
import 'package:rental_app/features/tickets/presentation/pages/ticket_page.dart';
import 'package:rental_app/features/apartments/presentation/pages/apartment_detail_page.dart';
import 'package:rental_app/features/apartments/presentation/pages/apartments_page.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/presentation/pages/account_type_page.dart';
import 'package:rental_app/features/auth/presentation/pages/change_password_page.dart';
import 'package:rental_app/features/auth/presentation/pages/login_page.dart';
import 'package:rental_app/features/auth/presentation/pages/profile_page.dart';
import 'package:rental_app/features/auth/presentation/pages/signup_page.dart';
import 'package:rental_app/features/auth/presentation/pages/welcome_page.dart';
import 'package:rental_app/features/dashboard/presentation/pages/home_page.dart';
import 'package:rental_app/features/payments/presentation/pages/receipt_page.dart';
import 'package:rental_app/features/payments/presentation/pages/tenant_receipt_page.dart';
import 'package:rental_app/features/receipts/presentation/check_receipt_page.dart';
import 'package:rental_app/features/receipts/presentation/report_receipt_problem_page.dart';
import 'package:rental_app/features/repairs/presentation/new_repair_page.dart';
import 'package:rental_app/features/properties/presentation/pages/agreement_editor_page.dart';
import 'package:rental_app/features/tenant_access/presentation/pages/tenant_tabs.dart';
import 'package:rental_app/features/payments/presentation/pages/record_payment_page.dart';
import 'package:rental_app/features/properties/presentation/pages/members_page.dart';
import 'package:rental_app/features/properties/presentation/pages/properties_page.dart';
import 'package:rental_app/features/properties/presentation/pages/property_detail_page.dart';
import 'package:rental_app/features/properties/presentation/pages/property_form_page.dart';
import 'package:rental_app/features/tenancies/presentation/pages/start_tenancy_page.dart';
import 'package:rental_app/features/tenancies/presentation/pages/tenancies_page.dart';
import 'package:rental_app/features/tenancies/presentation/pages/tenancy_detail_page.dart';
import 'package:rental_app/features/tenant_access/presentation/pages/join_with_code_page.dart';
import 'package:rental_app/features/tenant_access/presentation/pages/my_rental_page.dart';
import 'package:rental_app/shared/widgets/app_shell.dart';
import 'package:rental_app/shared/widgets/geometric_backdrop.dart';

/// Route paths in one place, so screens never hardcode strings like '/login'.
class AppRoutes {
  AppRoutes._();

  // Logged out
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String signup = '/signup'; // step 1: choose the account type
  static const String signupDetails = '/signup/details'; // step 2: name, username, password

  /// e.g. /signup/details?type=tenant
  static String signupDetailsFor(AccountType type) =>
      Uri(path: signupDetails, queryParameters: {'type': type.value}).toString();

  // The four tabs of the bottom bar
  static const String home = '/home';
  static const String properties = '/properties';
  static const String tenants = '/tenants';
  static const String profile = '/profile';

  // Tenants' extra tabs (instead of Properties and Tenants)
  static const String myBills = '/my-bills';
  static const String myPayments = '/my-payments';
  static const String myIssues = '/my-issues';

  // Pages opened on top of a tab (the bottom bar stays visible)
  static const String changePassword = '/change-password';
  static const String joinWithCode = '/profile/join';
  static const String admin = '/profile/admin';
  // The tenant's home and receipts open inside the Home tab (bottom bar stays).
  static String myRental(String tenancyId) => '/home/my-home/$tenancyId';
  static String newTicket(String tenancyId) => '/home/my-home/$tenancyId/report';
  static String myReceipt(String tenancyId, String paymentId) =>
      '/home/my-home/$tenancyId/receipts/$paymentId';
  static String reportReceiptProblem(String tenancyId, String paymentId) =>
      '/home/my-home/$tenancyId/receipts/$paymentId/problem';
  static const String checkReceipt = '/profile/check-receipt';
  static String ticket(String ticketId) => '/my-issues/$ticketId';
  static const String myAnnouncements = '/home/announcements';
  static String announcements(String propertyId) => '/properties/$propertyId/announcements';
  static String newAnnouncement(String propertyId) => '/properties/$propertyId/announcements/new';
  static String propertyTickets(String propertyId) => '/properties/$propertyId/tickets';
  static String bills(String propertyId) => '/properties/$propertyId/bills';
  static String newBill(String propertyId) => '/properties/$propertyId/bills/new';
  static String billTypes(String propertyId) => '/properties/$propertyId/bills/types';
  static String bill(String propertyId, String billId) => '/properties/$propertyId/bills/$billId';
  static String billForUnit(String propertyId, String tenancyId) =>
      Uri(path: newBill(propertyId), queryParameters: {'tenancy': tenancyId}).toString();
  /// A message to one tenant; [title] and [body] pre-fill it (e.g. a reminder).
  static String messageTenant(String propertyId, String tenantId, {String? title, String? body}) => Uri(
        path: newAnnouncement(propertyId),
        queryParameters: {'tenant': tenantId, 'title': ?title, 'body': ?body},
      ).toString();
  static String agreement(String propertyId) => '/properties/$propertyId/agreement';
  static String unitAgreement(String propertyId, String apartmentId) =>
      '/properties/$propertyId/apartments/$apartmentId/agreement';
  static String newRepair(String propertyId, String apartmentId, {String? ticketId}) => Uri(
        path: '/properties/$propertyId/apartments/$apartmentId/repairs/new',
        queryParameters: ticketId == null ? null : {'ticket': ticketId},
      ).toString();
  static const String newProperty = '/properties/new';
  static String propertyDetail(String id) => '/properties/$id';
  static String editProperty(String id) => '/properties/$id/edit';
  static String propertyMembers(String id) => '/properties/$id/members';
  static String apartments(String propertyId) => '/properties/$propertyId/apartments';
  static String apartmentDetail(String propertyId, String apartmentId) =>
      '/properties/$propertyId/apartments/$apartmentId';
  static String startTenancy(String propertyId, String apartmentId) =>
      '/properties/$propertyId/apartments/$apartmentId/start-tenancy';
  static String tenancyDetail(String propertyId, String tenancyId) =>
      '/properties/$propertyId/tenancies/$tenancyId';
  static String recordPayment(String propertyId, String tenancyId) =>
      '/properties/$propertyId/tenancies/$tenancyId/pay';
  static String receipt(String propertyId, String paymentId) =>
      '/properties/$propertyId/receipts/$paymentId';

  /// Screens anyone can see without being logged in.
  static const Set<String> loggedOutOnly = {welcome, login, signup, signupDetails};
}

/// A GoRoute whose page sits on the app's background with faint shapes
/// (GeometricBackdrop). Always a MaterialPage, so pages animate the usual
/// Android way and each page carries its own background while animating.
class AppRoute extends GoRoute {
  AppRoute({required super.path, required GoRouterWidgetBuilder builder, super.routes})
      : super(
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: state.name ?? state.path,
            arguments: state.extra,
            restorationId: state.pageKey.value,
            child: GeometricBackdrop(child: builder(context, state)),
          ),
        );
}

/// The app's router, exposed as a Riverpod provider.
/// Screens navigate with `context.go(...)` (replace the current screen, e.g.
/// switching tabs) or `context.push(...)` (open on top, with a back button).
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseClientProvider).auth;
  final authRepository = ref.watch(authRepositoryProvider);

  // Re-run `redirect` below every time the user logs in or out.
  final authChanges = _StreamListenable(auth.onAuthStateChange);
  ref.onDispose(authChanges.dispose);

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: authChanges,

    // Runs before every navigation. Returning a path sends the user there;
    // returning null lets them continue where they were going.
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final onLoggedOutScreen = AppRoutes.loggedOutOnly.contains(state.matchedLocation);

      if (!loggedIn && !onLoggedOutScreen) return AppRoutes.welcome;

      // Logged in with a temporary password (after an owner/manager reset
      // it): nothing else until a new password is chosen.
      final mustChange = loggedIn && authRepository.mustChangePassword;
      final onChangePassword = state.matchedLocation == AppRoutes.changePassword;
      if (mustChange && !onChangePassword) return AppRoutes.changePassword;

      if (loggedIn && onLoggedOutScreen) return AppRoutes.home;
      return null;
    },

    routes: [
      // ---------------- logged out ----------------
      AppRoute(path: AppRoutes.welcome, builder: (_, _) => const WelcomePage()),
      AppRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
      AppRoute(
        path: AppRoutes.signup,
        builder: (_, _) => const AccountTypePage(),
        routes: [
          AppRoute(
            path: 'details',
            builder: (_, state) => SignupPage(
              accountType: AccountType.fromJson(state.uri.queryParameters['type']) ??
                  AccountType.landlord,
            ),
          ),
        ],
      ),

      // ---------------- the tabs (bottom bar) ----------------
      // Each branch keeps its own state, so switching tabs doesn't reset them.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            AppRoute(
              path: AppRoutes.home,
              builder: (_, _) => const HomePage(),
              routes: [
                AppRoute(path: 'announcements', builder: (_, _) => const MyAnnouncementsPage()),
                // The tenant's home: inside the Home tab, so the bar stays.
                AppRoute(
                  path: 'my-home/:tenancyId',
                  builder: (_, state) => MyRentalPage(tenancyId: state.pathParameters['tenancyId']!),
                  routes: [
                    AppRoute(
                      path: 'report',
                      builder: (_, state) => NewTicketPage(tenancyId: state.pathParameters['tenancyId']!),
                    ),
                    AppRoute(
                      path: 'receipts/:paymentId',
                      builder: (_, state) => TenantReceiptPage(
                        tenancyId: state.pathParameters['tenancyId']!,
                        paymentId: state.pathParameters['paymentId']!,
                      ),
                      routes: [
                        AppRoute(
                          path: 'problem',
                          builder: (_, state) => ReportReceiptProblemPage(
                            tenancyId: state.pathParameters['tenancyId']!,
                            paymentId: state.pathParameters['paymentId']!,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            AppRoute(
              path: AppRoutes.properties,
              builder: (_, _) => const PropertiesPage(),
              routes: [
                // 'new' before ':propertyId', or "new" would be read as an id.
                AppRoute(path: 'new', builder: (_, _) => const PropertyFormPage()),
            AppRoute(
              path: ':propertyId',
              builder: (_, state) => PropertyDetailPage(propertyId: state.pathParameters['propertyId']!),
              routes: [
                AppRoute(
                  path: 'edit',
                  builder: (_, state) => PropertyFormPage(propertyId: state.pathParameters['propertyId']),
                ),
                AppRoute(
                  path: 'agreement',
                  builder: (_, state) => AgreementEditorPage(propertyId: state.pathParameters['propertyId']!),
                ),
                AppRoute(
                  path: 'members',
                  builder: (_, state) => MembersPage(propertyId: state.pathParameters['propertyId']!),
                ),
                AppRoute(
                  path: 'announcements',
                  builder: (_, state) => AnnouncementsPage(propertyId: state.pathParameters['propertyId']!),
                  routes: [
                    AppRoute(
                      path: 'new',
                      builder: (_, state) => NewAnnouncementPage(
                        propertyId: state.pathParameters['propertyId']!,
                        // ?tenant=<id>: a message to that one tenant (from a unit page)
                        tenantId: state.uri.queryParameters['tenant'],
                        title: state.uri.queryParameters['title'],
                        body: state.uri.queryParameters['body'],
                      ),
                    ),
                  ],
                ),
                AppRoute(
                  path: 'tickets',
                  builder: (_, state) => PropertyTicketsPage(propertyId: state.pathParameters['propertyId']!),
                ),
                AppRoute(
                  path: 'bills',
                  builder: (_, state) => BillsPage(propertyId: state.pathParameters['propertyId']!),
                  routes: [
                    // 'new' and 'types' before ':billId', or they'd be read as ids.
                    AppRoute(
                      path: 'new',
                      builder: (_, state) => NewBillPage(
                        propertyId: state.pathParameters['propertyId']!,
                        // ?tenancy=<id>: a bill for that one unit (from a unit page)
                        tenancyId: state.uri.queryParameters['tenancy'],
                      ),
                    ),
                    AppRoute(
                      path: 'types',
                      builder: (_, state) => BillTypesPage(propertyId: state.pathParameters['propertyId']!),
                    ),
                    AppRoute(
                      path: ':billId',
                      builder: (_, state) => BillPage(
                        propertyId: state.pathParameters['propertyId']!,
                        billId: state.pathParameters['billId']!,
                      ),
                    ),
                  ],
                ),
                AppRoute(
                  path: 'apartments',
                  builder: (_, state) => ApartmentsPage(propertyId: state.pathParameters['propertyId']!),
                  routes: [
                    AppRoute(
                      path: ':apartmentId',
                      builder: (_, state) => ApartmentDetailPage(
                        propertyId: state.pathParameters['propertyId']!,
                        apartmentId: state.pathParameters['apartmentId']!,
                      ),
                      routes: [
                        AppRoute(
                          path: 'start-tenancy',
                          builder: (_, state) => StartTenancyPage(
                            propertyId: state.pathParameters['propertyId']!,
                            apartmentId: state.pathParameters['apartmentId']!,
                          ),
                        ),
                        AppRoute(
                          path: 'repairs/new',
                          builder: (_, state) => NewRepairPage(
                            propertyId: state.pathParameters['propertyId']!,
                            apartmentId: state.pathParameters['apartmentId']!,
                            ticketId: state.uri.queryParameters['ticket'],
                          ),
                        ),
                        AppRoute(
                          path: 'agreement',
                          builder: (_, state) => AgreementEditorPage(
                            propertyId: state.pathParameters['propertyId']!,
                            apartmentId: state.pathParameters['apartmentId'],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                AppRoute(
                  path: 'tenancies/:tenancyId',
                  builder: (_, state) => TenancyDetailPage(
                    propertyId: state.pathParameters['propertyId']!,
                    tenancyId: state.pathParameters['tenancyId']!,
                  ),
                  routes: [
                    AppRoute(
                      path: 'pay',
                      builder: (_, state) => RecordPaymentPage(
                        propertyId: state.pathParameters['propertyId']!,
                        tenancyId: state.pathParameters['tenancyId']!,
                      ),
                    ),
                  ],
                ),
                AppRoute(
                  path: 'receipts/:paymentId',
                  builder: (_, state) => ReceiptPage(
                    propertyId: state.pathParameters['propertyId']!,
                    paymentId: state.pathParameters['paymentId']!,
                  ),
                ),
              ],
            ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            AppRoute(path: AppRoutes.tenants, builder: (_, _) => const TenanciesPage()),
          ]),
          StatefulShellBranch(routes: [
            AppRoute(
              path: AppRoutes.profile,
              builder: (_, _) => const ProfilePage(),
              routes: [
                AppRoute(path: 'join', builder: (_, _) => const JoinWithCodePage()),
                AppRoute(path: 'admin', builder: (_, _) => const AdminPage()),
                AppRoute(path: 'check-receipt', builder: (_, _) => const CheckReceiptPage()),
              ],
            ),
          ]),
          // Tenants only (see AppShell): branches 4, 5 and 6.
          StatefulShellBranch(routes: [
            AppRoute(path: AppRoutes.myBills, builder: (_, _) => const MyBillsTab()),
          ]),
          StatefulShellBranch(routes: [
            AppRoute(path: AppRoutes.myPayments, builder: (_, _) => const MyPaymentsTab()),
          ]),
          StatefulShellBranch(routes: [
            AppRoute(
              path: AppRoutes.myIssues,
              builder: (_, _) => const MyIssuesTab(),
              routes: [
                // Any ticket, for tenants and the team. Opened from another
                // tab it still shows with the bottom bar.
                AppRoute(
                  path: ':ticketId',
                  builder: (_, state) => TicketPage(ticketId: state.pathParameters['ticketId']!),
                ),
              ],
            ),
          ]),
        ],
      ),

      // ---------------- full-screen (no bottom bar) ----------------
      // Every other page lives inside a tab, so the bottom bar always shows.
      // A forced password change after a reset: nothing else until it's done.
      AppRoute(
        path: AppRoutes.changePassword,
        builder: (_, _) => ChangePasswordPage(forced: authRepository.mustChangePassword),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('Page not found')),
    ),
  );
});

/// Adapts a Stream (Supabase auth events) to a Listenable (what GoRouter's
/// refreshListenable expects): every stream event notifies the router.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
