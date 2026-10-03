import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xui_manager/main.dart';
import 'package:xui_manager/models/models.dart';
import 'package:xui_manager/state/app_state.dart';

Future<AppState> _stateWithPanels(String lang) async {
  SharedPreferences.setMockInitialValues({'lang': lang});
  FlutterSecureStorage.setMockInitialValues({});
  final state = AppState();
  await state.load();
  for (var i = 0; i < 5; i++) {
    await state.upsert(PanelConfig(
      id: 'p$i',
      name: 'Panel $i',
      type: PanelType.values[i % 3],
      url: 'https://h$i.example.com:2053/path',
      username: 'u',
      password: 'p',
    ));
  }
  return state;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  for (final lang in ['en', 'fa']) {
    testWidgets('5 panels: list, home and switcher render on a phone ($lang)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final state = await tester.runAsync(() => _stateWithPanels(lang));
      await tester.pumpWidget(
          ChangeNotifierProvider.value(value: state!, child: const XuiManagerApp()));
      await _settle(tester);

      expect(find.text('Panel 0'), findsOneWidget);
      expect(find.text(lang == 'en' ? 'Add panel' : 'افزودن پنل'), findsOneWidget);

      await tester.tap(find.text('Panel 0'));
      await _settle(tester);
      expect(find.text(lang == 'en' ? 'Server status' : 'وضعیت سرور'), findsOneWidget);
      expect(find.text(lang == 'en' ? 'Edit panel' : 'ویرایش پنل'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
      await _settle(tester);
      expect(find.text(lang == 'en' ? 'Switch panel' : 'تعویض پنل'), findsOneWidget);
      expect(find.text('Panel 4'), findsOneWidget);

      // Switch to another panel.
      await tester.tap(find.text('Panel 3'));
      await _settle(tester);
      expect(find.text('Panel 3'), findsOneWidget);

      // Let pending network timeouts finish, then tear the tree down.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  }
}
