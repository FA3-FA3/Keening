# Desktop (Windows) build

One codebase builds both targets: `flutter build web` and `flutter build windows --release`
(`scripts/build-windows.ps1`). Platform code lives behind conditional exports in `lib/utils/`
(`*_web.dart` for the browser, `*_io.dart` for the desktop, `*_stub.dart` for tests).

Desktop equivalents: image paste/copy (`pasteboard`), file drag-and-drop (`desktop_drop`),
exports and save dialogs (`file_selector`), local settings (`%APPDATA%\Keening\settings.json`).
The desktop app talks to the live API (`productionApiUrl` in `api_client.dart`) unless built with
`--dart-define=API_BASE_URL=...`, and signs in with the web app's Firebase keys.

Status: not compiled or run yet - Visual Studio's C++ workload is not installed on this machine.
Check image paste, drag-and-drop, exports and sign-in on a real build. Google sign-in popups may
need extra setup on desktop.
