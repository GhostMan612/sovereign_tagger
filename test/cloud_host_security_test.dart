// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sovereign_tagger/core/cloud_pcloud.dart';
import 'package:sovereign_tagger/core/cloud_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pCloud OAuth redirect accepts an approved regional API host', () {
    final result = PCloudProvider.parseAuthRedirect(
      'sovereigntagger://pcloud/callback#access_token=example&locationid=2&hostname=eapi.pcloud.com',
    );
    expect(result, isNotNull);
    expect(result!.apiHost, 'eapi.pcloud.com');
  });

  test('pCloud OAuth redirect rejects an arbitrary API host', () {
    final result = PCloudProvider.parseAuthRedirect(
      'sovereigntagger://pcloud/callback#access_token=example&hostname=attacker.example',
    );
    expect(result, isNull);
  });

  test('pCloud refuses to persist a token with an unapproved host', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await CloudSettings.load(prefs);
    await expectLater(
      CloudSettings.setToken(token: 'example', apiHost: 'attacker.example', locationId: 1),
      throwsA(isA<ArgumentError>()),
    );
    expect(CloudSettings.hasToken, isFalse);
  });

  test('pCloud does not reactivate a token with a poisoned stored host', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pcloud_token': 'existing-secret',
      'pcloud_api_host': 'attacker.example',
    });
    final prefs = await SharedPreferences.getInstance();
    await CloudSettings.load(prefs);
    expect(CloudSettings.hasToken, isFalse);
    expect(CloudSettings.apiHost, isEmpty);
  });
}
