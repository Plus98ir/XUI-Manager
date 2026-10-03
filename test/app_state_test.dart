import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xui_manager/models/models.dart';
import 'package:xui_manager/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppState', () {
    test('allows at most maxPanels panels', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final state = AppState();
      await state.load();
      for (var i = 0; i < AppState.maxPanels; i++) {
        await state.upsert(PanelConfig(
            id: 'p$i', name: 'Panel $i', type: PanelType.values[i % 3], url: 'https://h$i.com'));
      }
      expect(state.panels, hasLength(AppState.maxPanels));
      expect(state.canAddPanel, isFalse);
      expect(
          () => state.upsert(const PanelConfig(
              id: 'extra', name: 'x', type: PanelType.marzban, url: 'https://x.com')),
          throwsStateError);
      // Editing an existing panel still works at the limit.
      await state.upsert(const PanelConfig(
          id: 'p0', name: 'Renamed', type: PanelType.threeXui, url: 'https://h0.com'));
      expect(state.panelById('p0')!.name, 'Renamed');

      final reloaded = AppState();
      await reloaded.load();
      expect(reloaded.panels, hasLength(AppState.maxPanels));
    });
  });
}
