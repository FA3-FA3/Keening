import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'router.dart';
import 'widgets/app_dropdown.dart';
import 'utils/app_colors.dart';
import 'utils/clipboard_image.dart';
import 'utils/file_drop.dart';
import 'utils/window_chrome.dart';
import 'widgets/app_logo.dart';

const useAuthEmulator =
    kDebugMode && bool.fromEnvironment('USE_EMULATOR', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  listenForPastedImages();
  await initWindowChrome();
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

/// On pages without a top bar of their own (sign-in and so on) the desktop app
/// still needs a way to move, minimise and close the window.
class _WithTitleBar extends StatelessWidget {
  const _WithTitleBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: topBarHasWindowControls,
    builder: (context, own, _) => Column(
      children: [
        if (!own)
          Material(
            color: AppColors.navBackground,
            child: WindowDragArea(
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const AppLogo(height: 13.5),
                  const SizedBox(width: 8),
                  Text(
                    'Keening',
                    style: TextStyle(color: AppColors.navBrand, fontSize: 13),
                  ),
                  const Spacer(),
                  const WindowControls(height: 32),
                ],
              ),
            ),
          ),
        Expanded(child: child),
      ],
    ),
  );
}

class KeeningApp extends StatelessWidget {
  const KeeningApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Keening',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      dropdownMenuTheme: appDropdownMenuTheme,
      menuTheme: appMenuTheme,
      popupMenuTheme: appPopupMenuTheme,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryLight),
      scaffoldBackgroundColor: AppColors.backgroundLight,
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      dropdownMenuTheme: appDropdownMenuTheme,
      menuTheme: appMenuTheme,
      popupMenuTheme: appPopupMenuTheme,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryDark,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
    ),
    routerConfig: appRouter,
    // Files dropped on the desktop app's window reach the editors.
    builder: (context, child) => FileDropHost(
      child: hasCustomTitleBar
          ? _WithTitleBar(child: child ?? const SizedBox())
          : (child ?? const SizedBox()),
    ),
  );
}
