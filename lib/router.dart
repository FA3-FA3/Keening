import 'package:go_router/go_router.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'utils/auth_notifier.dart';
import 'widgets/app_shell.dart';

final AuthNotifier authNotifier = AuthNotifier();

final GoRouter appRouter = GoRouter(
  refreshListenable: authNotifier,
  redirect: (context, state) {
    final dashboard =
        state.uri.path == '/dashboard' ||
        state.uri.path.startsWith('/dashboard/');
    if (!authNotifier.isSignedIn && dashboard) return '/login';
    if (authNotifier.isSignedIn && state.uri.path == '/login') {
      return '/dashboard';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardPage(),
    ),
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(currentPath: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomePage()),
      ],
    ),
  ],
);
