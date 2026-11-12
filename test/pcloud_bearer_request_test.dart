// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/cloud_pcloud.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OAuth API URLs contain no bearer token', () {
    final uri = PCloudProvider.buildApiRequestUri(
      'api.pcloud.com',
      'listfolder',
      {'folderid': '0'},
    );
    expect(uri.scheme, 'https');
    expect(uri.host, 'api.pcloud.com');
    expect(uri.queryParameters['folderid'], '0');
    expect(uri.queryParameters.containsKey('auth'), isFalse);
    expect(uri.queryParameters.containsKey('access_token'), isFalse);
  });

  test('both legacy auth and OAuth token query injection are rejected', () {
    expect(
      () => PCloudProvider.buildApiRequestUri(
        'api.pcloud.com',
        'listfolder',
        {'auth': 'secret'},
      ),
      throwsArgumentError,
    );
    expect(
      () => PCloudProvider.buildApiRequestUri(
        'eapi.pcloud.com',
        'userinfo',
        {'access_token': 'secret'},
      ),
      throwsArgumentError,
    );
  });

  test('unexpected API hosts are rejected before requests', () {
    expect(
      () => PCloudProvider.buildApiRequestUri(
        'attacker.example',
        'userinfo',
        const {},
      ),
      throwsArgumentError,
    );
  });
}
