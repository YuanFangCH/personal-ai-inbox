import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'pages/calendar_page.dart';
import 'pages/conversation_page.dart';
import 'pages/global_knowledge_page.dart';
import 'pages/home_page.dart';
import 'pages/inbox_page.dart';
import 'pages/knowledge_page.dart';
import 'pages/matters_page.dart';
import 'pages/pending_page.dart';
import 'pages/settings_page.dart';
import 'pages/sync_page.dart';
import 'theme/app_design_tokens.dart';
import 'widgets/capture_sheet.dart';

enum AppPage {
  home('首页', Icons.space_dashboard_outlined),
  inbox('秘书', Icons.forum_outlined),
  calendar('日历', Icons.calendar_month_outlined),
  matters('事项', Icons.account_tree_outlined),
  knowledge('知识', Icons.menu_book_outlined),
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

class _AppShellState extends State<AppShell> {
  AppPage _page = AppPage.home;
  bool _startupChecked = false;
  String? _lastOpenedConversationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startupChecked) {
      return;
    }
    _startupChecked = true;
    _schedulePendingConversationOpen();
  }

  void _schedulePendingConversationOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final conversationId = AppScope.conversations(context)
          .consumePendingConversationId();
      if (conversationId != null &&
          conversationId != _lastOpenedConversationId) {
        _lastOpenedConversationId = conversationId;
        openConversationPage(context, conversationId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _schedulePendingConversationOpen();
    final runtime = AppScope.of(context);
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
          AppPage.matters => [runtime.results],
          AppPage.knowledge => const <Listenable>[],
          AppPage.sync => [runtime.results, runtime.sync],
          AppPage.settings => [runtime.results, runtime.preferences],
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
              child: _pageFor(
                _page,
                wide: wide,
                secretaryNavigation: constraints.maxWidth >= 600,
              ),
            ),
          ),
        );
        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
                  bottom: false,
                  child: wide && _page != AppPage.inbox
                      ? Row(
                          children: [
                            _WideNavigation(
                              selected: _page,
                              onSelected: (page) =>
                                  setState(() => _page = page),
                              extended: constraints.maxWidth >= 1220,
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: content),
                          ],
                        )
                      : content,
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
          floatingActionButton:
              constraints.maxWidth < 600 ||
                  _page == AppPage.home ||
                  _page == AppPage.inbox
              ? null
              : FloatingActionButton.extended(
                  key: const Key('capture_button'),
                  onPressed: () => showCaptureSheet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('收下'),
                  tooltip: '捕获',
                ),
          bottomNavigationBar: wide || _page == AppPage.inbox
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

  Widget _pageFor(
    AppPage page, {
    required bool wide,
    required bool secretaryNavigation,
  }) {
    return switch (page) {
      AppPage.home => const HomePage(),
      AppPage.inbox => InboxPage(
        isWide: secretaryNavigation,
        onReturnHome: () => setState(() => _page = AppPage.home),
        onNavigate: _navigateFromSecretary,
      ),
      AppPage.calendar => const CalendarPage(),
      AppPage.matters => const MattersPage(),
      AppPage.knowledge => const KnowledgePage(),
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
      _ => null,
    };
    if (page != null) {
      setState(() => _page = page);
      return;
    }
    final route = switch (destination) {
      'global_knowledge' => const GlobalKnowledgePage(),
      'pending' => const PendingPage(),
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
      AppPage.matters => Icons.account_tree,
      AppPage.knowledge => Icons.menu_book,
      AppPage.sync => Icons.sync,
      AppPage.settings => Icons.tune,
    };
  }
}
