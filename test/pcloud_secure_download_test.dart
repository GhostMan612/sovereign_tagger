// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/cloud_pcloud.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pCloud accepts HTTPS CDN and relative HTTPS redirect targets', () {
    final source = Uri.parse('https://c123.pcloud.com/download?file=sample');
    expect(PCloudProvider.requireSecureDownloadUri(source), source);
    final redirected = source.resolve('/signed/asset?token=public-download-ticket');
    expect(PCloudProvider.requireSecureDownloadUri(redirected), redirected);
  });

  test('pCloud rejects a downgrade during redirect resolution', () {
    final origin = Uri.parse('https://c123.pcloud.com/download');
    expect(
      () => PCloudProvider.requireSecureDownloadUri(
        origin.resolve('http://c123.pcloud.com/asset'),
      ),
      throwsA(isA<PCloudException>()),
    );
  });

  test('pCloud blocks local links, embedded credentials and non-TLS ports', () {
    const bad = <String>[
      'http://c123.pcloud.com/media',
      'https://localhost/media',
      'https://sub.localhost/media',
      'https://127.0.0.1/media',
      'https://[::1]/media',
      'https://token@c123.pcloud.com/media',
      'https://c123.pcloud.com:8080/media',
      'https://host.local/media',
    ];
    for (final value in bad) {
      expect(
        () => PCloudProvider.requireSecureDownloadUri(Uri.parse(value)),
        throwsA(isA<PCloudException>()),
        reason: value,
      );
    }
  });

  test('HTTPS scheme-relative CDN locations remain validated', () {
    final origin = Uri.parse('https://c123.pcloud.com/a');
    final target = origin.resolve('//cdn.pcloud.com/asset');
    expect(PCloudProvider.requireSecureDownloadUri(target).host, 'cdn.pcloud.com');
    expect(
      () => PCloudProvider.requireSecureDownloadUri(
        origin.resolve('//localhost/private'),
      ),
      throwsA(isA<PCloudException>()),
    );
  });
}
