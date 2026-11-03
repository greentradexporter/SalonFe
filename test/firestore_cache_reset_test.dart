import 'package:flutter_test/flutter_test.dart';
import 'package:nashik_salon_booking/services/firebase_bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<bool> reset(Future<void> Function() clear) => resetFirestoreCacheOnce(
    preferences: SharedPreferences.getInstance,
    clearPersistence: clear,
    timeout: const Duration(milliseconds: 200),
  );

  test('clears once per install, then never again', () async {
    // Phones that ran an old build can carry thousands of saved profile
    // writes; uploading them first held up loading the salon for hours.
    var clears = 0;
    expect(await reset(() async => clears++), isTrue);
    expect(await reset(() async => clears++), isFalse);
    expect(await reset(() async => clears++), isFalse);
    expect(clears, 1);
  });

  test(
    'retries on the next launch when Firestore had already started',
    () async {
      var attempts = 0;
      // clearPersistence refuses once Firestore is running in this process.
      expect(
        await reset(() async {
          attempts++;
          throw StateError('Persistence cannot be cleared after use');
        }),
        isFalse,
      );
      expect(await reset(() async => attempts++), isTrue);
      expect(attempts, 2);
    },
  );

  test('a phone without a backlog keeps its saved data', () async {
    // Clearing costs a cold start, which is what put slower phones on "Could
    // not load your salon" right after updating to build 56.
    var clears = 0;
    var asked = 0;
    Future<bool> check(bool big) => resetFirestoreCacheOnce(
      preferences: SharedPreferences.getInstance,
      clearPersistence: () async => clears++,
      needsClear: () async {
        asked++;
        return big;
      },
    );
    expect(await check(false), isFalse);
    // Answered once: no current build can build a backlog again.
    expect(await check(true), isFalse);
    expect(clears, 0);
    expect(asked, 1);
  });

  test('a phone carrying a backlog is cleared', () async {
    var clears = 0;
    expect(
      await resetFirestoreCacheOnce(
        preferences: SharedPreferences.getInstance,
        clearPersistence: () async => clears++,
        needsClear: () async => true,
      ),
      isTrue,
    );
    expect(clears, 1);
  });

  test('a clear that hangs never blocks startup and is retried', () async {
    final started = DateTime.now();
    expect(
      await reset(() => Future<void>.delayed(const Duration(seconds: 30))),
      isFalse,
    );
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 5)),
    );
    expect(await reset(() async {}), isTrue);
  });
}
