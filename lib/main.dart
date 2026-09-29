import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'router.dart';
import 'utils/app_colors.dart';

const useAuthEmulator =
    kDebugMode && bool.fromEnvironment('USE_EMULATOR', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (useAuthEmulator) {
      // demoProjectId otherwise names the app "demo-keening", while the
      // shared FirebaseAuth.instance expects the default app.
      await Firebase.initializeApp(
        name: '[DEFAULT]',
        demoProjectId: 'demo-keening',
      );
      await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    runApp(const KeeningApp());
  } catch (error) {
    debugPrint('Keening authentication startup failed: $error');
    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Text('Keening is unavailable. Please try again later.'),
          ),
        ),
      ),
    );
  }
}

class KeeningApp extends StatelessWidget {
  const KeeningApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Keening',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryLight),
      scaffoldBackgroundColor: AppColors.backgroundLight,
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryDark,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
    ),
    routerConfig: appRouter,
  );
}
