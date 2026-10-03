// Renders every main screen with real fonts at phone size (360x780) in
// Farsi and English, saving PNGs to test/goldens/ for visual review, and
// fails on any layout overflow. Local only:
//   flutter test --tags screenshots --update-goldens
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xui_manager/api/panel_api.dart';
import 'package:xui_manager/l10n.dart';
import 'package:xui_manager/models/models.dart';
import 'package:xui_manager/screens/dashboard_tab.dart';
import 'package:xui_manager/screens/inbound_form_screen.dart';
import 'package:xui_manager/screens/inbounds_tab.dart';
import 'package:xui_manager/screens/outbounds_screen.dart';
import 'package:xui_manager/screens/panel_home_screen.dart';
import 'package:xui_manager/screens/panel_settings_screen.dart';
import 'package:xui_manager/screens/panels_screen.dart';
import 'package:xui_manager/screens/routing_screen.dart';
import 'package:xui_manager/screens/settings_screen.dart';
import 'package:xui_manager/screens/user_detail_screen.dart';
import 'package:xui_manager/screens/user_form_screen.dart';
import 'package:xui_manager/screens/users_tab.dart';
import 'package:xui_manager/state/app_state.dart';
import 'package:xui_manager/theme.dart';
import 'package:xui_manager/widgets/panel_switcher.dart';

import 'support/fake_api.dart';

Future<void> _loadFonts() async {
  Future<ByteData> read(String path) async =>
      ByteData.view(Uint8List.fromList(await File(path).readAsBytes()).buffer);
  final vazir = FontLoader('Vazirmatn');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    vazir.addFont(read('assets/fonts/Vazirmatn-$w.ttf'));
  }
  await vazir.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(read(icons.path))).load();
  }
}

void main() {
  late AppState state;
  final overflows = <String>[];

  setUpAll(() async {
    await _loadFonts();
    PanelApi.factoryOverride = FakeApi.new;
  });

  for (final (lang, mode, style) in [
    ('fa', ThemeMode.dark, AppStyle.aurora),
    ('en', ThemeMode.light, AppStyle.frost),
    ('fa', ThemeMode.light, AppStyle.aurora),
    ('en', ThemeMode.dark, AppStyle.frost),
  ]) {
    final tag = '${lang}_${mode.name}_${style.name}';
    group('$tag screens', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({'lang': lang, 'theme': mode.name, 'style': style.name});
        FlutterSecureStorage.setMockInitialValues({});
        state = AppState();
        await state.load();
        for (final (i, t) in [PanelType.threeXui, PanelType.alireza, PanelType.marzban].indexed) {
          await state.upsert(PanelConfig(
            id: 'p$i',
            name: ['آلمان Hetzner', 'Turkey Gaming server with a long name', 'Marzban NL'][i],
            type: t,
            url: 'https://dash.example$i.com:2053/secret',
            token: 't',
          ));
        }
      });

      Future<void> shot(WidgetTester tester, String name, Widget home,
          {Future<void> Function()? before}) async {
        tester.view.physicalSize = const Size(720, 1560);
        tester.view.devicePixelRatio = 2;
        // Real shadows instead of the test binding's black outlines.
        debugDisableShadows = false;
        addTearDown(tester.view.reset);
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final msg = d.exceptionAsString();
          if (msg.contains('overflowed')) {
            overflows.add('$tag/$name: ${msg.split('\n').first} @ ${d.context}');
          } else {
            prev?.call(d);
          }
        };
        await tester.pumpWidget(ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(lang),
            supportedLocales: S.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            themeMode: mode,
            theme: buildTheme(Brightness.light, style),
            darkTheme: buildTheme(Brightness.dark, style),
            home: home,
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        if (before != null) await before();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${tag}_$name.png'));
        FlutterError.onError = prev;
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }

      final api = FakeApi(const PanelConfig(id: 'p0', name: 'x', type: PanelType.threeXui, url: 'https://x'));

      testWidgets('panels', (t) => shot(t, '01_panels', const PanelsScreen()));
      testWidgets('home', (t) => shot(t, '02_home', const PanelHomeScreen(panelId: 'p0')));
      testWidgets('home scrolled', (t) => shot(t, '03_home_bottom', const PanelHomeScreen(panelId: 'p0'),
          before: () async {
            await t.drag(find.byType(ListView).first, const Offset(0, -500));
            await t.pump(const Duration(milliseconds: 500));
          }));
      testWidgets('switcher', (t) => shot(t, '04_switcher', const PanelHomeScreen(panelId: 'p0'),
          before: () async {
            showPanelSwitcher(t.element(find.byType(PanelHomeScreen)), currentId: 'p0');
            for (var i = 0; i < 5; i++) {
              await t.pump(const Duration(milliseconds: 300));
            }
          }));
      testWidgets('users', (t) => shot(t, '05_users', Scaffold(body: SafeArea(child: UsersTab(api: api))),
          before: () async {
            // Two polls so the live speed tag appears.
            await t.pump(const Duration(seconds: 6));
            await t.pump(const Duration(milliseconds: 300));
          }));
      testWidgets('user detail', (t) async {
        final user = (await api.users()).first;
        await shot(t, '06_user_detail', UserDetailScreen(api: api, user: user));
      });
      testWidgets('user form', (t) => shot(t, '07_user_form', UserFormScreen(api: api)));
      testWidgets('user form bottom', (t) => shot(t, '08_user_form_bottom', UserFormScreen(api: api),
          before: () async {
            await t.drag(find.byType(ListView).first, const Offset(0, -900));
            await t.pump(const Duration(milliseconds: 500));
          }));
      testWidgets('user edit', (t) async {
        final user = (await api.users())[1];
        await shot(t, '09_user_edit', UserFormScreen(api: api, user: user));
      });
      testWidgets('inbound picker', (t) => shot(t, '10_inbound_picker', UserFormScreen(api: api),
          before: () async {
            await t.tap(find.byIcon(Icons.hub_outlined));
            for (var i = 0; i < 5; i++) {
              await t.pump(const Duration(milliseconds: 300));
            }
          }));
      testWidgets('inbounds', (t) => shot(t, '11_inbounds', Scaffold(body: SafeArea(child: InboundsTab(api: api, active: true)))));
      testWidgets('inbound new', (t) => shot(t, '12_inbound_new', InboundFormScreen(api: api)));
      testWidgets('inbound reality', (t) => shot(t, '13_inbound_reality', InboundFormScreen(api: api, inboundId: 21),
          before: () async {
            await t.drag(find.byType(ListView).first, const Offset(0, -700));
            await t.pump(const Duration(milliseconds: 500));
          }));
      testWidgets('inbound hysteria', (t) => shot(t, '21_inbound_hysteria', InboundFormScreen(api: api, inboundId: 31),
          before: () async {
            await t.drag(find.byType(ListView).first, const Offset(0, -700));
            await t.pump(const Duration(milliseconds: 500));
          }));
      testWidgets('inbound wireguard', (t) => shot(t, '22_inbound_wireguard', InboundFormScreen(api: api, inboundId: 32),
          before: () async {
            await t.drag(find.byType(ListView).first, const Offset(0, -500));
            await t.pump(const Duration(milliseconds: 500));
          }));
      testWidgets('inbound mixed', (t) => shot(t, '23_inbound_mixed', InboundFormScreen(api: api, inboundId: 33),
          before: () async {
            await t.drag(find.byType(ListView).first, const Offset(0, -500));
            await t.pump(const Duration(milliseconds: 500));
          }));
      testWidgets('inbound tuic', (t) => shot(t, '24_inbound_tuic', InboundFormScreen(api: api, inboundId: 34),
          before: () async {
            await t.drag(find.byType(ListView).first, const Offset(0, -500));
            await t.pump(const Duration(milliseconds: 500));
          }));
      testWidgets('inbound protocols', (t) => shot(t, '25_inbound_protocols', InboundFormScreen(api: api),
          before: () async {
            await t.tap(find.text('VLESS').first);
            for (var i = 0; i < 5; i++) {
              await t.pump(const Duration(milliseconds: 300));
            }
          }));
      testWidgets('settings', (t) => shot(t, '14_settings', PanelSettingsScreen(api: api)));
      testWidgets('outbounds', (t) => shot(t, '15_outbounds', OutboundsScreen(api: api)));
      testWidgets('routing', (t) => shot(t, '16_routing', RoutingScreen(api: api)));
      testWidgets('rule form', (t) => shot(
          t,
          '17_rule_form',
          RuleFormScreen(
            rule: const {
              'type': 'field',
              'outboundTag': 'warp',
              'domain': ['geosite:openai', 'domain:claude.ai'],
              'protocol': ['tls'],
            },
            targets: const ['direct', 'blocked', 'warp'],
            inboundTags: const ['inbound-2542', 'inbound-3103'],
          )));
      testWidgets('status', (t) => shot(t, '19_status', Scaffold(body: SafeArea(child: DashboardTab(api: FakeApi(api.config), active: true))),
          before: () async {
            for (var i = 0; i < 40; i++) {
              await t.pump(const Duration(seconds: 2));
            }
          }));
      testWidgets('status bottom', (t) => shot(t, '20_status_bottom', Scaffold(body: SafeArea(child: DashboardTab(api: FakeApi(api.config), active: true))),
          before: () async {
            for (var i = 0; i < 40; i++) {
              await t.pump(const Duration(seconds: 2));
            }
            await t.drag(find.byType(ListView).first, const Offset(0, -700));
            await t.pump(const Duration(milliseconds: 500));
          }));
      testWidgets('app settings', (t) => shot(t, '18_app_settings', const SettingsScreen()));
    });
  }

  tearDownAll(() {
    PanelApi.factoryOverride = null;
    if (overflows.isNotEmpty) {
      fail('Layout overflows:\n${overflows.join('\n')}');
    }
  });
}
