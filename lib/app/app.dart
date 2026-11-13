import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/design.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/playlists/presentation/playlists_screen.dart';
import '../features/search/presentation/search_screen.dart';
import 'app_controller.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();

class GlyphApp extends ConsumerStatefulWidget {
  const GlyphApp({super.key});
  @override
  ConsumerState<GlyphApp> createState() => _GlyphAppState();
}

class _GlyphAppState extends ConsumerState<GlyphApp> {
  static const navigation = MethodChannel('glyph/navigation');
  late final AppLifecycleListener lifecycle;
  @override
  void initState() {
    super.initState();
    lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(ref.read(controllerProvider).scanPhoneAudio(automatic: true));
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref
              .read(controllerProvider)
              .scanPhoneAudio(requestPermission: true, automatic: true),
        );
      }
    });
    navigation.setMethodCallHandler((call) async {
      if (call.method == 'open' && mounted) {
        final route = _widgetRoute(
          call.arguments as String?,
          ref.read(controllerProvider),
        );
        if (route != null) navigatorKey.currentState?.push(route);
      }
    });
  }

  @override
  void dispose() {
    lifecycle.dispose();
    navigation.setMethodCallHandler(null);
    super.dispose();
  }

  Route<void>? _widgetRoute(String? name, AppController c) => switch (name) {
    '/queue' => MaterialPageRoute<void>(builder: (_) => QueueScreen(c: c)),
    '/playlists' => MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Your playlists')),
        body: LivePage(
          c: c,
          builder: (_) => PlaylistsScreen(c: c),
        ),
      ),
    ),
    _ => null,
  };
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(controllerProvider);
    return ListenableBuilder(
      listenable: c,
      builder: (_, _) {
        if (c.notice != null) {
          final message = c.notice!;
          c.notice = null;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => messengerKey.currentState
              ?..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message))),
          );
        }
        return MaterialApp(
          title: 'Glyph Music',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: messengerKey,
          navigatorKey: navigatorKey,
          onGenerateRoute: (settings) => _widgetRoute(settings.name, c),
          theme: glyphTheme(Brightness.light, accentColour: c.accentColour),
          darkTheme: glyphTheme(Brightness.dark, accentColour: c.accentColour),
          themeMode: c.theme,
          home: GlyphShell(c: c),
        );
      },
    );
  }
}

class GlyphShell extends StatefulWidget {
  const GlyphShell({super.key, required this.c});
  final AppController c;
  @override
  State<GlyphShell> createState() => _GlyphShellState();
}

class _GlyphShellState extends State<GlyphShell> {
  final pages = PageController();
  int tab = 0;
  Timer? _exitTimer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onInactive: _resetExit);
  }

  void _resetExit() {
    if (_exitTimer == null) return;
    _exitTimer?.cancel();
    _exitTimer = null;
    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      _resetExit();
      return;
    }
    if (_exitTimer != null) {
      _resetExit();
      unawaited(SystemNavigator.pop());
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press Back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
    _exitTimer = Timer(const Duration(seconds: 2), () => _exitTimer = null);
  }

  void selectTab(int index) {
    _resetExit();
    FocusManager.instance.primaryFocus?.unfocus();
    if (MediaQuery.disableAnimationsOf(context)) {
      pages.jumpToPage(index);
    } else {
      unawaited(
        pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeInOutCubic,
        ),
      );
    }
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _lifecycle.dispose();
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: pages,
                      physics: const _SmoothPagePhysics(),
                      onPageChanged: (index) {
                        _resetExit();
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => tab = index);
                      },
                      children: [
                        _KeepAlivePage(
                          child: HomeScreen(
                            c: c,
                            onLibrary: () => selectTab(2),
                            onSearch: () => selectTab(1),
                          ),
                        ),
                        _KeepAlivePage(child: SearchScreen(c: c)),
                        _KeepAlivePage(child: LibraryScreen(c: c)),
                        _KeepAlivePage(child: PlaylistsScreen(c: c)),
                      ],
                    ),
                  ),
                  if (c.current != null) MiniPlayer(c: c),
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: NavigationBar(
                      selectedIndex: tab,
                      onDestinationSelected: selectTab,
                      height: 74,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.grid_view_outlined),
                          selectedIcon: Icon(Icons.grid_view_rounded),
                          label: 'Home',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.search),
                          label: 'Search',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.library_music_outlined),
                          selectedIcon: Icon(Icons.library_music),
                          label: 'Library',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.queue_music_outlined),
                          label: 'Playlists',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmoothPagePhysics extends ScrollPhysics {
  const _SmoothPagePhysics({super.parent});

  @override
  _SmoothPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _SmoothPagePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 180, ratio: 1);
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}

class LivePage extends StatelessWidget {
  const LivePage({super.key, required this.c, required this.builder});
  final AppController c;
  final Widget Function(BuildContext) builder;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => builder(context),
  );
}

void openPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
