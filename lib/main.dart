import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:go_router/go_router.dart';
import 'router.dart';
import 'widgets/app_dropdown.dart';
import 'utils/app_colors.dart';
import 'utils/app_look.dart';
import 'utils/app_mode.dart';
import 'utils/ui_colours.dart';
import 'utils/retro_theme.dart';
import 'utils/clipboard_image.dart';
import 'utils/file_drop.dart';
import 'utils/remembered_login.dart';
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
    // The desktop app signs in again by itself with the login remembered on
    // this device, so it does not ask every time it starts.
    await restoreRememberedLogin(
      signedIn: FirebaseAuth.instance.currentUser != null,
      store: loginStore,
      signIn: (email, password) => FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password),
      codeOf: (e) => e is FirebaseAuthException ? e.code : '',
    );
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
            color: AppColors.navBackgroundOf(context),
            child: WindowDragArea(
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const AppLogo(height: 13.5),
                  const SizedBox(width: 8),
                  Text(
                    'Keening',
                    style: TextStyle(
                      color: AppColors.navBrandOf(context),
                      fontSize: 13,
                    ),
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
  const KeeningApp({super.key, this.router});

  /// The pages of the app (tests give their own).
  final GoRouter? router;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([appLook, uiColours, appMode]),
    builder: (context, _) {
      final look = appLook.value;
      final colours = uiColours.value;
      final retro = look == AppLook.retro;
      final mode = appMode.value;
      final dark = mode == AppMode.dark;
      return MaterialApp.router(
        title: 'Keening',
        debugShowCheckedModeBanner: false,
        // Light or dark is the person's choice, not the device's.
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        theme: retro
            ? retroTheme(primary: colours.primary, desktop: colours.accent)
            : ThemeData(
                useMaterial3: true,
                fontFamily: 'Roboto',
                dropdownMenuTheme: appDropdownMenuTheme,
                menuTheme: appMenuTheme,
                popupMenuTheme: appPopupMenuTheme,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: colours.primary ?? AppColors.primaryLight,
                ).copyWith(secondary: colours.accent),
                scaffoldBackgroundColor: AppColors.backgroundLight,
              ),
        darkTheme: retro
            ? retroTheme(
                primary: colours.primary,
                desktop: colours.accent,
                brightness: Brightness.dark,
              )
            : ThemeData(
                useMaterial3: true,
                fontFamily: 'Roboto',
                dropdownMenuTheme: appDropdownMenuTheme,
                menuTheme: appMenuTheme,
                popupMenuTheme: appPopupMenuTheme,
                brightness: Brightness.dark,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: colours.primary ?? AppColors.primaryDark,
                  brightness: Brightness.dark,
                ).copyWith(secondary: colours.accent),
                scaffoldBackgroundColor: AppColors.backgroundDark,
              ),
        routerConfig: router ?? appRouter,
        // Files dropped on the desktop app's window reach the editors.
        builder: (context, child) {
          Widget app = FileDropHost(
            child: hasCustomTitleBar
                ? _WithTitleBar(child: child ?? const SizedBox())
                : (child ?? const SizedBox()),
          );
          if (retro) {
            // The pixel font is small for its size.
            final media = MediaQuery.of(context);
            app = MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(
                  media.textScaler.scale(1) * Retro.textScale,
                ),
              ),
              child: app,
            );
          }
          return app;
        },
      );
    },
  );
}
