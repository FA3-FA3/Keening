import 'dart:async';
import 'dart:convert';
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

import 'boards_page.dart';
import '../utils/local_store.dart';
import '../utils/pads_service.dart';
import 'documents_page.dart';
import 'projects_page.dart';
import '../utils/window_chrome.dart';
import '../utils/gantt_service.dart';
import '../utils/remembered_login.dart';
import '../utils/messages_service.dart';
import '../utils/people_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/fixed_width.dart';
import '../widgets/quick_add_panel.dart';
import 'calendar_page.dart';
import 'messages_page.dart';
import 'people_page.dart';
import 'schedule_page.dart';
import 'overview_page.dart';

const _dashboardTabs = [
  'Dashboard',
  'Projects',
  'Calendar',
  'Boards',
  'Schedule',
  'Documents',
  'People',
];

/// The least width the page area and the top bar are laid out at. In a narrower
/// space they keep it and scroll sideways, rather than squeezing their contents.
const _pageMinWidth = 560.0;
const _topBarMinWidth = 600.0;
const _navigationRadius = BorderRadius.all(Radius.circular(22));
const _navigationHeight = 36.0;

/// True in the mobile layout: the app is taller than it is wide.
bool _portrait(BuildContext context) =>
    MediaQuery.orientationOf(context) == Orientation.portrait;

/// The mobile layout is more compact: the top bar is 25% shorter and the strip
/// of open tabs 10% shorter.
double _topBarHeight(BuildContext context) => _portrait(context) ? 48 : 64;
double _tabHeight(BuildContext context) =>
    _portrait(context) ? _navigationHeight * 0.9 : _navigationHeight;
double _tabStripPadding(BuildContext context) =>
    _portrait(context) ? 6 * 0.9 : 6;
const _navigationWidth = 144.0;

/// Authenticated dashboard shell: sidebar nav + a workspace area. Tabs and
/// workspace are placeholders — swap in real content per tab as features
/// are built.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    this.loadProfile,
    this.padsService,
    this.peopleService,
    this.messagesService,
    this.ganttService,
    this.viewKey,
  });

  /// Replaces the Gantt service of Gantt calendar documents (tests give a fake).
  final GanttService? ganttService;

  /// Where the open tabs are remembered, so a reload of the page comes back to
  /// the same view. By default it is per signed-in user; without one (or in
  /// tests that do not ask for it) nothing is remembered.
  final String? viewKey;
  final Future<Map<String, dynamic>> Function()? loadProfile;

  /// Replaces the documents service (tests give a fake one).
  final PadsService? padsService;

  /// Replace the people and messages services (tests give fake ones). The
  /// unread message count in the top bar is only looked up when one of them is
  /// given or the app is signed in.
  final PeopleService? peopleService;
  final MessagesService? messagesService;

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
    if (page == 'Gantt') {
      _openGanttCalendar(result);
      return;
    }
    _searchTargets[page] = {...result};
    _openTab(page);
  }

  String? _selectedTab = 'Dashboard';
  bool _quickAddOpen = false;

  /// How many messages are waiting, shown on the top bar's messages button.
  int _unreadMessages = 0;
  Timer? _unreadTimer;
  MessagesService? _unreadService;

  /// The friend a conversation is to be opened with (from the People page).
  String? _messagesWith;

  void _startUnreadPolling() {
    final injected = widget.messagesService;
    if (injected == null && Firebase.apps.isEmpty) return;
    _unreadService = injected ?? MessagesService();
    Future<void> check() async {
      try {
        final r = await _unreadService!.call('unreadCount');
        if (mounted) {
          setState(() => _unreadMessages = (r['unread'] as int?) ?? 0);
        }
      } catch (_) {
        // The count is only a nicety; the next check tries again.
      }
    }

    check();
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (_) => check());
  }

  void _openMessages([String? username]) {
    setState(() => _messagesWith = username);
    _openTab('Messages');
  }

  /// Bumped for a page when quick add creates something for it, so the page
  /// loads afresh and shows the new item.
  final Map<String, int> _pageRevision = {};

  ValueKey<String> _pageKey(String tab) => ValueKey(
    _pageRevision[tab] == null
        ? 'workspace-page-$tab'
        : 'workspace-page-$tab-${_pageRevision[tab]}',
  );

  /// A Gantt calendar is a document: this opens it in a tab (a phase, if the
  /// target names one, is brought up in it).
  void _openGanttCalendar(Map<String, dynamic> target) {
    final id = target['parentId'];
    if (id is! String) return;
    final name =
        target['parent'] ?? target['name'] ?? target['title'] ?? 'Gantt';
    final tab = 'doc:$id';
    _docTabs[tab] = {'id': id, 'name': '$name', 'kind': 'gantt'};
    if (target['type'] == 'Phase') {
      _docTargets[tab] = {...target};
    } else {
      _docTargets.remove(tab);
    }
    _openTab(tab);
  }

  /// What to bring up inside a document tab (a phase of a Gantt calendar).
  final Map<String, Map<String, dynamic>> _docTargets = {};

  void _quickAdded(String tab) => setState(() {
    for (final t in {tab, 'Dashboard'}) {
      _pageRevision[t] = (_pageRevision[t] ?? 0) + 1;
    }
    // A new phase belongs to a calendar document that may be open.
    if (tab == 'Gantt') {
      for (final entry in _docTabs.entries) {
        if (entry.value['kind'] == 'gantt') {
          _pageRevision[entry.key] = (_pageRevision[entry.key] ?? 0) + 1;
        }
      }
    }
    if (tab == 'Schedule' || tab == 'Calendar') _scheduleRefresh++;
  });
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => topBarHasWindowControls.value = true,
    );
    _startUnreadPolling();
    _restoreView();
    _loadProfile();
  }

  // ----------------------------------------------- remembering the view

  String? get _viewStoreKey {
    if (widget.viewKey != null) return widget.viewKey;
    if (Firebase.apps.isEmpty) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'keening.view.$uid';
  }

  String? _lastSavedView;

  /// Document tabs that were brought back by a reload (not opened just now).
  final Set<String> _restoredDocTabs = {};

  /// Remembers which tabs are open and which one is showing (and which
  /// documents the document tabs hold), for the next time the page loads.
  void _persistView() {
    final key = _viewStoreKey;
    if (key == null) return;
    final json = jsonEncode({
      'tabs': _openTabs,
      'selected': _selectedTab,
      'collapsed': _sidebarCollapsed,
      'docs': {
        for (final e in _docTabs.entries)
          e.key: {
            'id': e.value['id'],
            'name': e.value['name'],
            'kind': e.value['kind'],
          },
      },
    });
    if (json == _lastSavedView) return;
    _lastSavedView = json;
    localWrite(key, json);
  }

  /// Brings back the tabs remembered by [_persistView]. Anything that does not
  /// look right is ignored, so a damaged or old record just starts afresh.
  void _restoreView() {
    final key = _viewStoreKey;
    final raw = key == null ? null : localRead(key);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final known = {..._dashboardTabs, 'Settings', 'Messages'};
      final docs = <String, Map<String, dynamic>>{};
      if (data['docs'] is Map) {
        (data['docs'] as Map).forEach((tab, doc) {
          if (tab is String &&
              tab.startsWith('doc:') &&
              doc is Map &&
              doc['id'] is String &&
              doc['name'] is String) {
            docs[tab] = Map<String, dynamic>.from(doc);
          }
        });
      }
      final tabs = <String>[];
      for (final t in (data['tabs'] as List? ?? [])) {
        // Each tab once, and only ones that exist.
        if (t is String &&
            !_openTabs.contains(t) &&
            !tabs.contains(t) &&
            (known.contains(t) || docs.containsKey(t))) {
          tabs.add(t);
        }
      }
      if (tabs.isEmpty && data['selected'] != 'Dashboard') return;
      for (final t in tabs) {
        _openTabs.add(t);
        _tabKeys[t] = GlobalKey();
        if (docs.containsKey(t)) {
          _docTabs[t] = docs[t]!;
          _restoredDocTabs.add(t);
        }
      }
      final selected = data['selected'];
      _selectedTab = selected is String && _openTabs.contains(selected)
          ? selected
          : _openTabs.last;
      if (data['collapsed'] == true) _sidebarCollapsed = true;
      _lastSavedView = raw;
    } catch (_) {
      // A damaged record: start afresh.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => topBarHasWindowControls.value = false,
    );
    _unreadTimer?.cancel();
    if (widget.messagesService == null) _unreadService?.close();
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

  /// Documents open in tabs of their own, by tab name (`doc:<id>`).
  final Map<String, Map<String, dynamic>> _docTabs = {};

  /// What a tab is called: a page's name, or a document's.
  String _tabTitle(String tab) =>
      _docTabs[tab]?['name'] as String? ?? tab.split('/').last;

  /// Opens [document] in a tab of its own (or goes to the one already open).
  void _openDocumentTab(Map<String, dynamic> document) {
    final tab = 'doc:${document['id']}';
    _docTabs[tab] = {...document};
    _openTab(tab);
  }

  /// Keeps the document tabs in step with the Documents page: a renamed
  /// document renames its tab, a deleted one closes it.
  void _syncDocumentTabs(List<Map<String, dynamic>> documents) {
    if (!mounted || _docTabs.isEmpty) return;
    for (final tab in List.of(_docTabs.keys)) {
      final id = _docTabs[tab]!['id'];
      final current = documents.where((d) => d['id'] == id).firstOrNull;
      if (current == null) {
        _closeTab(tab);
      } else if (current['name'] != _docTabs[tab]!['name']) {
        setState(() => _docTabs[tab] = {..._docTabs[tab]!, ...current});
        _persistView();
      }
    }
  }

  final Map<String, GlobalKey> _tabKeys = {'Dashboard': GlobalKey()};

  void _openTab(String tab) {
    setState(() {
      if (!_openTabs.contains(tab)) {
        _openTabs.add(tab);
        _tabKeys[tab] = GlobalKey();
      }
      _selectedTab = tab;
    });
    _persistView();
    _revealActiveTab();
  }

  String? _draggingTab;

  /// Wide enough for the whole label plus the drag handle, padding and close button.
  double _tabWidth(String tab) {
    final painter = TextPainter(
      text: TextSpan(
        text: _tabTitle(tab),
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
      _persistView();
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
        height: _tabHeight(context),
        child: Center(child: Text(_tabTitle(tab))),
      ),
    ),
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Tooltip(
        message: 'Drag to reorder ${_tabTitle(tab)}',
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
      _docTabs.remove(tab);
      _restoredDocTabs.remove(tab);
      if (_hoveredTab == tab) _hoveredTab = null;
      if (_selectedTab == tab) {
        _selectedTab = _openTabs.isEmpty
            ? null
            : _openTabs[index < _openTabs.length ? index : index - 1];
      }
    });
    _persistView();
    _revealActiveTab();
  }

  Future<void> _logOut() async {
    if (Firebase.apps.isEmpty) return;
    try {
      // Signing out forgets the login kept on this device.
      try {
        await loginStore?.clear();
      } catch (_) {
        // Nothing more can be done about storage that will not clear.
      }
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
          body: Stack(
            children: [
              Column(
                children: [
                  Visibility(
                    visible: !_fullscreen,
                    maintainState: true,
                    child: _TopBar(
                      username: (_profile?['username'] as String?) ?? 'Account',
                      picture: _profile?['profilePicture'] as String?,
                      onSettings: () => _openTab('Settings'),
                      unreadMessages: _unreadMessages,
                      onMessages: _openMessages,
                      onQuickAdd: () =>
                          setState(() => _quickAddOpen = !_quickAddOpen),
                      quickAddOpen: _quickAddOpen,
                      onSearch: _search,
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
                            onToggle: () {
                              setState(
                                () => _sidebarCollapsed = !_sidebarCollapsed,
                              );
                              _persistView();
                            },
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
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: _tabStripPadding(
                                                      context,
                                                    ),
                                                  ),
                                                  child: _draggableTab(
                                                    tab,
                                                    MouseRegion(
                                                      onEnter: (_) => setState(
                                                        () => _hoveredTab = tab,
                                                      ),
                                                      onExit: (_) {
                                                        if (mounted &&
                                                            _hoveredTab ==
                                                                tab) {
                                                          setState(
                                                            () => _hoveredTab =
                                                                null,
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
                                                                tab ==
                                                                    _selectedTab
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
                                                          height: _tabHeight(
                                                            context,
                                                          ),
                                                          width: _tabWidth(tab),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
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
                                                                      _tabTitle(
                                                                        tab,
                                                                      ),
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
                                                                    'Close ${_tabTitle(tab)}',
                                                                onPressed: () =>
                                                                    _closeTab(
                                                                      tab,
                                                                    ),
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
                                child: MinWidthScroll(
                                  minWidth: _pageMinWidth,
                                  child: _openTabs.isEmpty
                                      ? const SizedBox.expand(
                                          key: ValueKey('workspace-empty'),
                                        )
                                      : IndexedStack(
                                          index: _openTabs.indexOf(
                                            _selectedTab!,
                                          ),
                                          alignment: Alignment.topLeft,
                                          children: [
                                            for (final tab in _openTabs)
                                              tab.startsWith('doc:')
                                                  ? DocumentTab(
                                                      service:
                                                          widget.padsService,
                                                      key: _pageKey(tab),
                                                      ganttService:
                                                          widget.ganttService,
                                                      searchTarget:
                                                          _docTargets[tab],
                                                      closeIfMissing:
                                                          _restoredDocTabs
                                                              .contains(tab),
                                                      document: _docTabs[tab]!,
                                                      onClose: () =>
                                                          _closeTab(tab),
                                                    )
                                                  : tab == 'Dashboard'
                                                  ? OverviewPage(
                                                      key: _pageKey(
                                                        'Dashboard',
                                                      ),
                                                      active:
                                                          _selectedTab ==
                                                          'Dashboard',
                                                    )
                                                  : tab == 'Boards'
                                                  ? BoardsPage(
                                                      searchTarget:
                                                          _searchTargets['Boards'],
                                                      key: _pageKey('Boards'),
                                                    )
                                                  : tab == 'Projects'
                                                  ? ProjectsPage(
                                                      key: _pageKey('Projects'),
                                                      onOpenItem: (page, target) {
                                                        if (page == 'Gantt') {
                                                          _openGanttCalendar(
                                                            target,
                                                          );
                                                          return;
                                                        }
                                                        _searchTargets[page] =
                                                            target;
                                                        _openTab(page);
                                                      },
                                                    )
                                                  : tab == 'Documents'
                                                  ? DocumentsPage(
                                                      service:
                                                          widget.padsService,
                                                      ganttService:
                                                          widget.ganttService,
                                                      onOpenDocument:
                                                          _openDocumentTab,
                                                      onDocumentsChanged:
                                                          _syncDocumentTabs,
                                                      searchTarget:
                                                          _searchTargets['Documents'],
                                                      key: _pageKey(
                                                        'Documents',
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
                                                      onSavePicture:
                                                          _savePicture,
                                                      onChangeAccount:
                                                          _changeAccount,
                                                      onLogOut: _logOut,
                                                    )
                                                  : tab == 'People'
                                                  ? PeoplePage(
                                                      key: _pageKey('People'),
                                                      service:
                                                          widget.peopleService,
                                                      onMessage: _openMessages,
                                                    )
                                                  : tab == 'Messages'
                                                  ? MessagesPage(
                                                      key: _pageKey('Messages'),
                                                      service: widget
                                                          .messagesService,
                                                      peopleService:
                                                          widget.peopleService,
                                                      initialUsername:
                                                          _messagesWith,
                                                      onUnreadChanged: (n) {
                                                        if (n !=
                                                            _unreadMessages) {
                                                          WidgetsBinding
                                                              .instance
                                                              .addPostFrameCallback((
                                                                _,
                                                              ) {
                                                                if (mounted) {
                                                                  setState(
                                                                    () =>
                                                                        _unreadMessages =
                                                                            n,
                                                                  );
                                                                }
                                                              });
                                                        }
                                                      },
                                                    )
                                                  : tab == 'Schedule'
                                                  ? SchedulePage(
                                                      searchTarget:
                                                          _searchTargets['Schedule'],
                                                      key: _pageKey('Schedule'),
                                                      date: _scheduleDate,
                                                      openRequest:
                                                          _scheduleRequest,
                                                      refreshRequest:
                                                          _scheduleRefresh,
                                                    )
                                                  : CalendarPage(
                                                      searchTarget:
                                                          _searchTargets['Calendar'],
                                                      key: _pageKey('Calendar'),
                                                      onOpenSchedule:
                                                          _openSchedule,
                                                      onChanged: () => setState(
                                                        () =>
                                                            _scheduleRefresh++,
                                                      ),
                                                    ),
                                          ],
                                        ),
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
              if (_quickAddOpen)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: QuickAddPanel(
                    key: const ValueKey('quick-add-panel-host'),
                    padsService: widget.padsService,
                    onClose: () => setState(() => _quickAddOpen = false),
                    onCreated: _quickAdded,
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
    required this.unreadMessages,
    required this.onMessages,
    required this.onQuickAdd,
    required this.quickAddOpen,
    required this.onSearch,
  });

  final String username;
  final String? picture;
  final VoidCallback onSettings;
  final int unreadMessages;
  final VoidCallback onMessages;
  final VoidCallback onQuickAdd;
  final bool quickAddOpen;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return MinWidthScroll(
      minWidth: _topBarMinWidth,
      child: Container(
        key: const ValueKey('workspace-top-bar'),
        height: _topBarHeight(context),
        width: double.infinity,
        color: AppColors.navBackground,
        padding: EdgeInsets.only(
          left: hasCustomTitleBar ? 16 : 24,
          right: hasCustomTitleBar ? 0 : 24,
        ),
        child: WindowDragArea(
          child: Row(
            children: [
              if (hasCustomTitleBar) ...[
                const AppLogo(height: 22.5),
                const SizedBox(width: 10),
              ],
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
                  width: MediaQuery.sizeOf(context).width < 900 ? 220 : 260,
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
              IconButton(
                key: const ValueKey('quick-add'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Quick add',
                onPressed: onQuickAdd,
                isSelected: quickAddOpen,
                icon: const Icon(Icons.add_circle_outline),
                selectedIcon: const Icon(Icons.add_circle),
                color: AppColors.navText,
              ),
              IconButton(
                key: const ValueKey('messages-button'),
                visualDensity: VisualDensity.compact,
                tooltip: unreadMessages > 0
                    ? 'Messages ($unreadMessages unread)'
                    : 'Messages',
                onPressed: onMessages,
                color: AppColors.navText,
                icon: Badge(
                  key: const ValueKey('messages-badge'),
                  isLabelVisible: unreadMessages > 0,
                  label: Text(unreadMessages > 99 ? '99+' : '$unreadMessages'),
                  child: const Icon(Icons.chat_bubble_outline),
                ),
              ),
              ...[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width < 700
                        ? 150
                        : 280,
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
              ],
              if (hasCustomTitleBar) ...[
                const SizedBox(width: 16),
                WindowControls(height: _topBarHeight(context)),
              ],
            ],
          ),
        ),
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
