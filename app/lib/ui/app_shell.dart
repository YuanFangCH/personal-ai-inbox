import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/table_models.dart';
import '../modules/tables/table_migration_gate.dart';
import 'app_scope.dart';
import 'pages/calendar_page.dart';
import 'pages/global_knowledge_page.dart';
import 'pages/home_page.dart';
import 'pages/inbox_page.dart';
import 'pages/tables_page.dart';
import 'pages/table_migration_read_only_page.dart';
import 'pages/settings_page.dart';
import 'pages/sync_page.dart';
import 'pages/table_detail_page.dart';
import 'pages/widget_settings_page.dart';
import 'theme/app_design_tokens.dart';
import 'widgets/capture_sheet.dart';

enum AppPage {
  home('首页', Icons.space_dashboard_outlined),
  inbox('秘书', Icons.forum_outlined),
  calendar('日历', Icons.calendar_month_outlined),
  matters('表与笔记', Icons.table_chart_outlined),
  knowledge('全局知识库', Icons.lightbulb_outline),
  sync('同步', Icons.sync_outlined),
  settings('设置', Icons.tune_outlined);

  const AppPage(this.label, this.icon);

  final String label;
  final IconData icon;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  AppPage _page = AppPage.home;
  bool _startupChecked = false;
  bool _secretaryCreated = false;
  String? _pendingSecretaryConversationId;
  final Queue<String> _queuedSecretaryConversationIds = Queue<String>();
  Listenable? _observedConversations;
  Object? _observedHomeWidgetBridge;
  StreamSubscription<void>? _homeWidgetOpenTargetSubscription;
  bool _handlingHomeWidgetOpenTargets = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final conversations = AppScope.conversations(context);
    if (_observedConversations != conversations) {
      _observedConversations?.removeListener(_handlePendingConversationOpen);
      _observedConversations = conversations;
      conversations.addListener(_handlePendingConversationOpen);
    }
    final bridge = AppScope.of(context).homeWidgetBridge;
    if (!identical(_observedHomeWidgetBridge, bridge)) {
      unawaited(_homeWidgetOpenTargetSubscription?.cancel());
      _observedHomeWidgetBridge = bridge;
      _homeWidgetOpenTargetSubscription = bridge?.openTargets.listen(
        (_) => unawaited(_drainHomeWidgetOpenTargets()),
        onError: (Object error, StackTrace stackTrace) =>
            _handleHomeWidgetBridgeError(error, stackTrace),
      );
    }
    if (!_startupChecked) {
      _startupChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!AppScope.migrationGate(context).requiresReadOnly) {
          _handlePendingConversationOpen();
        }
        unawaited(_drainHomeWidgetOpenTargets());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainHomeWidgetOpenTargets());
    }
  }

  void _handlePendingConversationOpen() {
    if (!mounted) return;
    final conversations = AppScope.conversations(context);
    final pending = <String>[];
    String? id;
    while ((id = conversations.consumePendingConversationId()) != null) {
      pending.add(id!);
    }
    if (pending.isEmpty) return;
    setState(() {
      _queuedSecretaryConversationIds.addAll(pending);
      _secretaryCreated = true;
      _page = AppPage.inbox;
      _advanceSecretaryConversationRequest();
    });
  }

  void _advanceSecretaryConversationRequest() {
    _pendingSecretaryConversationId ??= _queuedSecretaryConversationIds.isEmpty
        ? null
        : _queuedSecretaryConversationIds.removeFirst();
  }

  void _onSecretaryConversationRequestHandled() {
    if (!mounted) return;
    setState(() {
      _pendingSecretaryConversationId = null;
      _advanceSecretaryConversationRequest();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _observedConversations?.removeListener(_handlePendingConversationOpen);
    unawaited(_homeWidgetOpenTargetSubscription?.cancel());
    super.dispose();
  }

  Future<void> _drainHomeWidgetOpenTargets() async {
    if (_handlingHomeWidgetOpenTargets || !mounted) {
      return;
    }
    final bridge = AppScope.of(context).homeWidgetBridge;
    if (bridge == null) return;
    final migrationGate = AppScope.migrationGate(context);
    _handlingHomeWidgetOpenTargets = true;
    try {
      Map<String, Object?>? target;
      while (mounted && (target = await bridge.takeOpenTarget()) != null) {
        if (migrationGate.requiresReadOnly) {
          continue;
        }
        await _handleHomeWidgetOpenTarget(target!);
      }
    } on PlatformException catch (error, stackTrace) {
      _handleHomeWidgetBridgeError(error, stackTrace);
    } on Object catch (error, stackTrace) {
      _handleHomeWidgetBridgeError(error, stackTrace);
    } finally {
      _handlingHomeWidgetOpenTargets = false;
    }
  }

  void _handleHomeWidgetBridgeError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    if (error is PlatformException) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('桌面卡片入口暂时不可用，请稍后重试。')));
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'home widget bridge',
      ),
    );
  }

  Future<void> _handleHomeWidgetOpenTarget(Map<String, Object?> target) async {
    if (!mounted || AppScope.migrationGate(context).requiresReadOnly) {
      return;
    }
    switch (target['kind']) {
      case 'settings':
        unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const WidgetSettingsPage()),
          ),
        );
        return;
      case 'table':
        await _openHomeWidgetTable(
          tableId: _optionalTargetString(target['table_id']),
        );
        return;
      case 'entry':
        await _openHomeWidgetTable(
          tableId: _optionalTargetString(target['table_id']),
          entryId: _optionalTargetString(target['entry_id']),
        );
        return;
    }
  }

  Future<void> _openHomeWidgetTable({
    required String? tableId,
    String? entryId,
  }) async {
    final runtime = AppScope.of(context);
    String? resolvedTableId = tableId;
    TableEntryDocument? entry;
    if (entryId != null) {
      entry = await runtime.tables.readEntry(entryId);
      if (!mounted || runtime.migrationGate.requiresReadOnly) return;
      if (entry == null || entry.deleted) {
        setState(() => _page = AppPage.matters);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('这条内容已被删除，已返回表列表。')));
        return;
      }
      resolvedTableId = entry.tableId;
    }

    final table = resolvedTableId == null
        ? null
        : await runtime.tables.readTable(resolvedTableId);
    if (!mounted || runtime.migrationGate.requiresReadOnly) return;
    if (table == null || table.deleted) {
      setState(() => _page = AppPage.matters);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这张表已不存在，已返回表列表。')));
      return;
    }
    setState(() => _page = AppPage.matters);
    final route = entryId == null
        ? MaterialPageRoute<void>(
            builder: (_) => TableDetailPage(tableId: table.id),
          )
        : MaterialPageRoute<void>(
            builder: (_) => TableEntryEditorPage(
              tableId: table.id,
              type: entry!.type,
              entry: entry,
            ),
          );
    unawaited(Navigator.of(context).push<void>(route));
  }

  @override
  Widget build(BuildContext context) {
    final migrationGate = AppScope.migrationGate(context);
    return AnimatedBuilder(
      animation: migrationGate,
      builder: (context, _) {
        if (migrationGate.requiresReadOnly) {
          return TableMigrationReadOnlyPage(gate: migrationGate);
        }
        return _buildMain(context);
      },
    );
  }

  Widget _buildMain(BuildContext context) {
    if (_page == AppPage.inbox) _secretaryCreated = true;
    final runtime = AppScope.of(context);
    final homeWidgets = runtime.homeWidgets;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1024;
        final List<Listenable> pageModules = switch (_page) {
          AppPage.home => [runtime.results, runtime.capture, runtime.sync],
          AppPage.inbox => [
            runtime.results,
            runtime.capture,
            runtime.sync,
            runtime.conversations,
          ],
          AppPage.calendar => [runtime.results, runtime.preferences],
          AppPage.matters => [runtime.tables, runtime.capture, runtime.results],
          AppPage.knowledge => const <Listenable>[],
          AppPage.sync => [runtime.results, runtime.sync],
          AppPage.settings => [
            runtime.results,
            runtime.preferences,
            ?homeWidgets,
          ],
        };
        final content = AnimatedBuilder(
          animation: Listenable.merge(pageModules),
          builder: (context, _) => AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppDesignTokens.pageTransition,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.006),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey('page_${_page.name}'),
              child: _page == AppPage.inbox
                  ? const SizedBox.shrink()
                  : _pageFor(_page),
            ),
          ),
        );
        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: Column(
            children: [
              if (runtime.migrationGate.migrationComplete &&
                  (runtime.migrationGate.preview?.hasLegacyContent ?? false))
                _MigratedSourceBanner(gate: runtime.migrationGate),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            SizedBox(
                              width: wide
                                  ? (constraints.maxWidth >= 1220 ? 197 : 73)
                                  : 0,
                              child: wide
                                  ? _WideNavigation(
                                      selected: _page,
                                      onSelected: (page) =>
                                          setState(() => _page = page),
                                      extended: constraints.maxWidth >= 1220,
                                    )
                                  : null,
                            ),
                            SizedBox(
                              width: wide ? 1 : 0,
                              child: wide
                                  ? const VerticalDivider(width: 1)
                                  : null,
                            ),
                            Expanded(child: _buildPageStack(content, wide)),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          runtime.sync,
                          runtime.conversations,
                        ]),
                        builder: (context, _) =>
                            runtime.sync.isBusy ||
                                runtime.conversations.isChatGenerating
                            ? const LinearProgressIndicator(minHeight: 2)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: _page == AppPage.home || _page == AppPage.inbox
              ? null
              : FloatingActionButton.extended(
                  key: const Key('capture_button'),
                  onPressed: () => showCaptureSheet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('收下'),
                  tooltip: '捕获',
                ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _compactIndex(_page),
                  onDestinationSelected: (index) {
                    if (index < 3) {
                      setState(() => _page = AppPage.values[index]);
                    } else {
                      _showMore();
                    }
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(
                        Icons.space_dashboard_outlined,
                        key: Key('nav_home'),
                      ),
                      selectedIcon: Icon(
                        Icons.space_dashboard,
                        key: Key('nav_home'),
                      ),
                      label: '首页',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inbox_outlined, key: Key('nav_inbox')),
                      selectedIcon: Icon(Icons.inbox, key: Key('nav_inbox')),
                      label: '秘书',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.calendar_month_outlined,
                        key: Key('nav_calendar'),
                      ),
                      selectedIcon: Icon(
                        Icons.calendar_month,
                        key: Key('nav_calendar'),
                      ),
                      label: '日历',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.grid_view_outlined,
                        key: Key('nav_more'),
                      ),
                      selectedIcon: Icon(Icons.grid_view, key: Key('nav_more')),
                      label: '更多',
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildPageStack(Widget content, bool wide) => Stack(
    fit: StackFit.expand,
    children: [
      if (_secretaryCreated)
        Offstage(
          offstage: _page != AppPage.inbox,
          child: TickerMode(
            enabled: _page == AppPage.inbox,
            child: ExcludeFocus(
              excluding: _page != AppPage.inbox,
              child: ExcludeSemantics(
                excluding: _page != AppPage.inbox,
                child: InboxPage(
                  key: const ValueKey('persistent_secretary'),
                  isWide: wide,
                  visible: _page == AppPage.inbox,
                  requestedConversationId: _pendingSecretaryConversationId,
                  onRequestHandled: _onSecretaryConversationRequestHandled,
                  onReturnHome: () => setState(() => _page = AppPage.home),
                  onNavigate: _navigateFromSecretary,
                ),
              ),
            ),
          ),
        ),
      if (_page != AppPage.inbox) content,
    ],
  );

  Widget _pageFor(AppPage page) {
    return switch (page) {
      AppPage.home => const HomePage(),
      AppPage.inbox => const SizedBox.shrink(),
      AppPage.calendar => const CalendarPage(),
      AppPage.matters => const TablesPage(),
      AppPage.knowledge => const GlobalKnowledgePage(),
      AppPage.sync => const SyncPage(),
      AppPage.settings => const SettingsPage(),
    };
  }

  void _navigateFromSecretary(String destination) {
    final page = switch (destination) {
      'home' => AppPage.home,
      'calendar' => AppPage.calendar,
      'matters' => AppPage.matters,
      'knowledge' => AppPage.knowledge,
      'settings' => AppPage.settings,
      'sync' => AppPage.sync,
      'pending' => AppPage.matters,
      _ => null,
    };
    if (page != null) {
      setState(() => _page = page);
      return;
    }
    final route = switch (destination) {
      'global_knowledge' => const GlobalKnowledgePage(),
      _ => null,
    };
    if (route != null) {
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => route));
    }
  }

  int _compactIndex(AppPage page) {
    if (page.index <= 2) {
      return page.index;
    }
    return 3;
  }

  Future<void> _showMore() async {
    final selected = await showModalBottomSheet<AppPage>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final page in const [
                  AppPage.matters,
                  AppPage.knowledge,
                  AppPage.sync,
                  AppPage.settings,
                ])
                  ListTile(
                    key: Key('sheet_nav_${page.name}'),
                    leading: Icon(page.icon),
                    title: Text(page.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, page),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _page = selected);
    }
  }
}

String? _optionalTargetString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

class _MigratedSourceBanner extends StatelessWidget {
  const _MigratedSourceBanner({required this.gate});

  final TableMigrationGate gate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: MaterialBanner(
        backgroundColor: colors.primaryContainer,
        leading: Icon(Icons.lock_outline, color: colors.onPrimaryContainer),
        content: Text(
          '表格式副本已生成。原始旧资料作为只读备份保留；全局知识仍按独立确认流程管理。',
          style: TextStyle(color: colors.onPrimaryContainer),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TableMigrationReadOnlyPage(gate: gate),
              ),
            ),
            child: const Text('查看旧资料'),
          ),
        ],
      ),
    );
  }
}

class _WideNavigation extends StatelessWidget {
  const _WideNavigation({
    required this.selected,
    required this.onSelected,
    required this.extended,
  });

  final AppPage selected;
  final ValueChanged<AppPage> onSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 196,
      selectedIndex: selected.index,
      onDestinationSelected: (index) => onSelected(AppPage.values[index]),
      leading: Padding(
        padding: EdgeInsets.fromLTRB(extended ? 16 : 0, 20, 0, 18),
        child: extended
            ? Row(
                children: [
                  Icon(Icons.all_inbox, color: theme.colorScheme.primary),
                  const SizedBox(width: 9),
                  Text(
                    '懒狗秘书',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : Icon(Icons.all_inbox, color: theme.colorScheme.primary),
      ),
      destinations: [
        for (final page in AppPage.values)
          NavigationRailDestination(
            icon: Icon(page.icon, key: Key('nav_${page.name}')),
            selectedIcon: Icon(
              _selectedIcon(page),
              key: Key('nav_${page.name}'),
            ),
            label: Text(page.label),
          ),
      ],
    );
  }

  IconData _selectedIcon(AppPage page) {
    return switch (page) {
      AppPage.home => Icons.space_dashboard,
      AppPage.inbox => Icons.forum,
      AppPage.calendar => Icons.calendar_month,
      AppPage.matters => Icons.table_chart,
      AppPage.knowledge => Icons.menu_book,
      AppPage.sync => Icons.sync,
      AppPage.settings => Icons.tune,
    };
  }
}
