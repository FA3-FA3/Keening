import 'dart:math' as math;
import '../widgets/global_search_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../utils/app_colors.dart';
import '../widgets/profile_avatar.dart';
import '../utils/api_client.dart';
import '../utils/account_service.dart';
import 'settings_page.dart';
import 'gantt_page.dart';
import 'boards_page.dart';
import 'documents_page.dart';
import 'calendar_page.dart';
import 'schedule_page.dart';
import 'overview_page.dart';

const _dashboardTabs = [
  'Dashboard',
  'Gantt',
  'Calendar',
  'Boards',
  'Schedule',
  'Documents',
];
const _navigationRadius = BorderRadius.all(Radius.circular(22));
const _navigationHeight = 36.0;
const _navigationWidth = 144.0;

/// Authenticated dashboard shell: sidebar nav + a workspace area. Tabs and
/// workspace are placeholders — swap in real content per tab as features
/// are built.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.loadProfile});
  final Future<Map<String, dynamic>> Function()? loadProfile;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final Map<String, Map<String, dynamic>> _searchTargets = {};
  Future<void> _search() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => GlobalSearchDialog(
        search: (query, offset) async {
          final token = await FirebaseAuth.instance.currentUser?.getIdToken();
          if (token == null) throw StateError('Please sign in again.');
          return _api.search(token, query, offset);
        },
      ),
    );
    if (!mounted || result == null) return;
    final page = result['page'] as String;
    _searchTargets[page] = {...result};
    _openTab(page);
  }

  String? _selectedTab = 'Dashboard';
  bool _sidebarCollapsed = false;
  bool _fullscreen = false;
  String? _hoveredTab;
  final _api = ApiClient();
  Map<String, dynamic>? _profile;
  bool _profileLoading = false;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (widget.loadProfile == null && Firebase.apps.isEmpty) return;
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });
    try {
      Map<String, dynamic> profile;
      if (widget.loadProfile != null) {
        profile = await widget.loadProfile!();
      } else {
        await FirebaseAuth.instance.currentUser?.reload();
        final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
        if (token == null) throw StateError('Please sign in again.');
        profile = await _api.whoami(token);
      }
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _profileError = 'Unable to load your profile. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<String> _changeAccount(
    String action,
    Map<String, String> values,
  ) async {
    if (action == 'username') {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw StateError('Please sign in again.');
      final result = await _api.changeUsername(token, values['username']!);
      if (mounted) setState(() => _profile = {...?_profile, ...result});
      return 'Username changed.';
    }
    return AccountService().change(action, values);
  }

  Future<void> _savePicture(String? image) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('Please sign in again.');
    final result = await _api.saveProfilePicture(token, image);
    if (mounted) setState(() => _profile = {...?_profile, ...result});
  }

  Color _tabColor(String tab) {
    final base = tab == _selectedTab
        ? AppColors.primary(context).withValues(alpha: .15)
        : AppColors.text(context).withValues(alpha: .06);
    return _hoveredTab == tab
        ? Color.alphaBlend(
            AppColors.primary(context).withValues(alpha: .12),
            base,
          )
        : base;
  }

  DateTime _scheduleDate = DateTime.now();
  int _scheduleRequest = 0, _scheduleRefresh = 0;
  void _openSchedule(DateTime date) {
    _scheduleDate = date;
    _scheduleRequest++;
    _openTab('Schedule');
  }

  final List<String> _openTabs = ['Dashboard'];
  final Map<String, GlobalKey> _tabKeys = {'Dashboard': GlobalKey()};

  void _openTab(String tab) {
    setState(() {
      if (!_openTabs.contains(tab)) {
        _openTabs.add(tab);
        _tabKeys[tab] = GlobalKey();
      }
      _selectedTab = tab;
    });
    _revealActiveTab();
  }

  String? _draggingTab;

  /// Wide enough for the whole label plus the drag handle, padding and close button.
  double _tabWidth(String tab) {
    final painter = TextPainter(
      text: TextSpan(
        text: tab.split('/').last,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    // handle 26 + label padding 32 + close button 48 + slack
    return math.max(_navigationWidth, painter.width + 26 + 32 + 48 + 8);
  }

  /// Drop target for a tab; tabs are dragged only from their handle.
  Widget _draggableTab(String tab, Widget child) => DragTarget<String>(
    onWillAcceptWithDetails: (details) => details.data != tab,
    onAcceptWithDetails: (details) => setState(() {
      final from = _openTabs.indexOf(details.data), to = _openTabs.indexOf(tab);
      if (from < 0 || to < 0) return;
      _openTabs.insert(to, _openTabs.removeAt(from));
    }),
    builder: (context, candidates, _) => Opacity(
      opacity: _draggingTab == tab ? .3 : 1,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: candidates.isEmpty
              ? null
              : Border(
                  left: BorderSide(color: AppColors.primary(context), width: 3),
                ),
        ),
        child: child,
      ),
    ),
  );

  Widget _dragHandle(String tab) => Draggable<String>(
    key: ValueKey('tab-drag-$tab'),
    data: tab,
    axis: Axis.horizontal,
    onDragStarted: () => setState(() => _draggingTab = tab),
    onDragEnd: (_) {
      if (mounted) setState(() => _draggingTab = null);
    },
    feedback: Material(
      elevation: 4,
      color: AppColors.surface(context),
      shape: const RoundedRectangleBorder(borderRadius: _navigationRadius),
      child: SizedBox(
        width: _navigationWidth,
        height: _navigationHeight,
        child: Center(child: Text(tab.split('/').last)),
      ),
    ),
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Tooltip(
        message: 'Drag to reorder ${tab.split('/').last}',
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(
            Icons.drag_indicator,
            size: 18,
            color: AppColors.text(context).withValues(alpha: .6),
          ),
        ),
      ),
    ),
  );

  void _revealActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _tabKeys[_selectedTab]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, alignment: 0.5);
      }
    });
  }

  void _closeTab(String tab) {
    if (!_openTabs.contains(tab)) return;
    setState(() {
      final index = _openTabs.indexOf(tab);
      _openTabs.removeAt(index);
      _tabKeys.remove(tab);
      if (_hoveredTab == tab) _hoveredTab = null;
      if (_selectedTab == tab) {
        _selectedTab = _openTabs.isEmpty
            ? null
            : _openTabs[index < _openTabs.length ? index : index - 1];
      }
    });
    _revealActiveTab();
  }

  Future<void> _logOut() async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) context.go('/');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to sign out. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_fullscreen) setState(() => _fullscreen = false);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.background(context),
          body: Column(
            children: [
              Visibility(
                visible: !_fullscreen,
                maintainState: true,
                child: _TopBar(
                  username: (_profile?['username'] as String?) ?? 'Account',
                  picture: _profile?['profilePicture'] as String?,
                  onSettings: () => _openTab('Settings'),
                  onSearch: _search,
                  onLogOut: _logOut,
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Visibility(
                      visible: !_fullscreen,
                      maintainState: true,
                      child: _Sidebar(
                        selectedTab: _selectedTab,
                        onSelect: _openTab,
                        collapsed: _sidebarCollapsed,
                        onToggle: () => setState(
                          () => _sidebarCollapsed = !_sidebarCollapsed,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Material(
                            color: AppColors.surface(context),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Visibility(
                                    visible: !_fullscreen,
                                    maintainState: true,
                                    child: SingleChildScrollView(
                                      key: const ValueKey(
                                        'workspace-tab-strip',
                                      ),
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (final tab in _openTabs)
                                            Padding(
                                              key: _tabKeys[tab],
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 6,
                                                  ),
                                              child: _draggableTab(
                                                tab,
                                                MouseRegion(
                                                  onEnter: (_) => setState(
                                                    () => _hoveredTab = tab,
                                                  ),
                                                  onExit: (_) {
                                                    if (mounted &&
                                                        _hoveredTab == tab) {
                                                      setState(
                                                        () =>
                                                            _hoveredTab = null,
                                                      );
                                                    }
                                                  },
                                                  child: Material(
                                                    key: ValueKey(
                                                      'tab-surface-$tab',
                                                    ),
                                                    color: _tabColor(tab),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          _navigationRadius,
                                                      side: BorderSide(
                                                        color:
                                                            tab == _selectedTab
                                                            ? AppColors.primary(
                                                                context,
                                                              )
                                                            : AppColors.text(
                                                                context,
                                                              ).withValues(
                                                                alpha: 0.12,
                                                              ),
                                                      ),
                                                    ),
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    child: SizedBox(
                                                      height: _navigationHeight,
                                                      width: _tabWidth(tab),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          _dragHandle(tab),
                                                          Expanded(
                                                            child: Semantics(
                                                              selected:
                                                                  tab ==
                                                                  _selectedTab,
                                                              child: TextButton(
                                                                key: ValueKey(
                                                                  'workspace-tab-$tab',
                                                                ),
                                                                onPressed: () =>
                                                                    _openTab(
                                                                      tab,
                                                                    ),
                                                                style:
                                                                    TextButton.styleFrom(
                                                                      shape: const RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            _navigationRadius,
                                                                      ),
                                                                      foregroundColor:
                                                                          tab ==
                                                                              _selectedTab
                                                                          ? AppColors.primary(
                                                                              context,
                                                                            )
                                                                          : AppColors.text(
                                                                              context,
                                                                            ),
                                                                      padding: const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            16,
                                                                        vertical:
                                                                            8,
                                                                      ),
                                                                    ).copyWith(
                                                                      overlayColor: WidgetStateProperty.resolveWith(
                                                                        (
                                                                          states,
                                                                        ) =>
                                                                            states.contains(
                                                                              WidgetState.hovered,
                                                                            )
                                                                            ? Colors.transparent
                                                                            : null,
                                                                      ),
                                                                    ),
                                                                child: Text(
                                                                  tab
                                                                      .split(
                                                                        '/',
                                                                      )
                                                                      .last,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          IconButton(
                                                            style: IconButton.styleFrom(
                                                              hoverColor: Colors
                                                                  .transparent,
                                                            ),
                                                            key: ValueKey(
                                                              'close-tab-$tab',
                                                            ),
                                                            tooltip:
                                                                'Close ${tab.split('/').last}',
                                                            onPressed: () =>
                                                                _closeTab(tab),
                                                            icon: const Icon(
                                                              Icons.close,
                                                              size: 18,
                                                            ),
                                                            color:
                                                                AppColors.text(
                                                                  context,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (_selectedTab != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: IconButton(
                                      key: const ValueKey(
                                        'workspace-fullscreen',
                                      ),
                                      tooltip: _fullscreen
                                          ? 'Exit fullscreen'
                                          : 'Fullscreen',
                                      onPressed: () => setState(
                                        () => _fullscreen = !_fullscreen,
                                      ),
                                      icon: Icon(
                                        _fullscreen
                                            ? Icons.close
                                            : Icons.fullscreen,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _openTabs.isEmpty
                                ? const SizedBox.expand(
                                    key: ValueKey('workspace-empty'),
                                  )
                                : IndexedStack(
                                    index: _openTabs.indexOf(_selectedTab!),
                                    alignment: Alignment.topLeft,
                                    children: [
                                      for (final tab in _openTabs)
                                        tab == 'Dashboard'
                                            ? OverviewPage(
                                                key: const ValueKey(
                                                  'workspace-page-Dashboard',
                                                ),
                                                active:
                                                    _selectedTab == 'Dashboard',
                                              )
                                            : tab == 'Gantt'
                                            ? GanttPage(
                                                searchTarget:
                                                    _searchTargets['Gantt'],
                                                key: ValueKey(
                                                  'workspace-page-Gantt',
                                                ),
                                              )
                                            : tab == 'Boards'
                                            ? BoardsPage(
                                                searchTarget:
                                                    _searchTargets['Boards'],
                                                key: ValueKey(
                                                  'workspace-page-Boards',
                                                ),
                                              )
                                            : tab == 'Documents'
                                            ? DocumentsPage(
                                                searchTarget:
                                                    _searchTargets['Documents'],
                                                key: const ValueKey(
                                                  'workspace-page-Documents',
                                                ),
                                              )
                                            : tab == 'Settings'
                                            ? SettingsPage(
                                                key: const ValueKey(
                                                  'workspace-page-Settings',
                                                ),
                                                profile: _profile,
                                                loading: _profileLoading,
                                                error: _profileError,
                                                onRefresh: _loadProfile,
                                                onSavePicture: _savePicture,
                                                onChangeAccount: _changeAccount,
                                              )
                                            : tab == 'Schedule'
                                            ? SchedulePage(
                                                searchTarget:
                                                    _searchTargets['Schedule'],
                                                key: const ValueKey(
                                                  'workspace-page-Schedule',
                                                ),
                                                date: _scheduleDate,
                                                openRequest: _scheduleRequest,
                                                refreshRequest:
                                                    _scheduleRefresh,
                                              )
                                            : CalendarPage(
                                                searchTarget:
                                                    _searchTargets['Calendar'],
                                                key: const ValueKey(
                                                  'workspace-page-Calendar',
                                                ),
                                                onOpenSchedule: _openSchedule,
                                                onChanged: () => setState(
                                                  () => _scheduleRefresh++,
                                                ),
                                              ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.username,
    this.picture,
    required this.onSettings,
    required this.onSearch,
    required this.onLogOut,
  });

  final String username;
  final String? picture;
  final VoidCallback onSettings;
  final VoidCallback onSearch;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      width: double.infinity,
      color: AppColors.navBackground,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            'Keening',
            style: TextStyle(
              color: AppColors.navBrand,
              fontSize: 18,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (MediaQuery.sizeOf(context).width >= 700)
            SizedBox(
              width: 260,
              child: OutlinedButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search),
                label: const Text('Search all pages'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navText,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Search all pages',
              onPressed: onSearch,
              icon: const Icon(Icons.search),
              color: AppColors.navText,
            ),
          const Spacer(),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width < 600 ? 150 : 280,
            ),
            child: TextButton.icon(
              key: const ValueKey('account-settings'),
              onPressed: onSettings,
              icon: ProfileAvatar(picture: picture, radius: 15),
              label: Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.navText,
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: onLogOut,
            child: Text(
              'Log Out',
              style: TextStyle(
                color: AppColors.navTextActive,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selectedTab,
    required this.onSelect,
    required this.collapsed,
    required this.onToggle,
  });
  final bool collapsed;
  final VoidCallback onToggle;

  final String? selectedTab;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    key: const ValueKey('workspace-sidebar'),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200),
    curve: Curves.easeInOut,
    width: collapsed
        ? 48
        : MediaQuery.sizeOf(context).width < 600
        ? 124
        : 190,
    color: AppColors.navBackground,
    child: Column(
      children: [
        Expanded(
          child: collapsed
              ? const SizedBox.expand()
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    for (final tab in _dashboardTabs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SizedBox(
                          height: 40,
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              Positioned(
                                left: -24,
                                right: 8,
                                top: 0,
                                bottom: 0,
                                child: Semantics(
                                  selected: selectedTab == tab,
                                  button: true,
                                  child: Material(
                                    color: selectedTab == tab
                                        ? AppColors.navTextActive.withValues(
                                            alpha: 0.15,
                                          )
                                        : AppColors.navText.withValues(
                                            alpha: 0.06,
                                          ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: _navigationRadius,
                                      side: BorderSide(
                                        color: selectedTab == tab
                                            ? AppColors.navTextActive
                                            : AppColors.navText.withValues(
                                                alpha: 0.12,
                                              ),
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      key: ValueKey('nav-$tab'),
                                      onTap: () => onSelect(tab),
                                      child: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.only(
                                          left: 40,
                                          right: 16,
                                        ),
                                        child: Text(
                                          tab,
                                          style: TextStyle(
                                            color: selectedTab == tab
                                                ? AppColors.navTextActive
                                                : AppColors.navText,
                                            fontSize: 15,
                                            fontWeight: selectedTab == tab
                                                ? FontWeight.w600
                                                : FontWeight.w300,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: IconButton(
              key: const ValueKey('toggle-sidebar'),
              tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
              onPressed: onToggle,
              color: AppColors.navText,
              icon: Icon(collapsed ? Icons.chevron_right : Icons.chevron_left),
            ),
          ),
        ),
      ],
    ),
  );
}
