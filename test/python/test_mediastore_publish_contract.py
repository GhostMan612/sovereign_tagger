"""Source-contract guard: MediaStore import cannot publish before integrity check.

This is a static regression check only; Android ContentResolver instrumentation
must still verify actual provider behavior on API 29+ devices.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "android/app/src/main/kotlin/com/sovereigntagger/StorageBridge.kt"


class MediaStorePublishOrderTests(unittest.TestCase):
    def test_pending_import_sha_is_verified_before_publishing(self):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("fun addToMediaStore(")
        end = source.index("fun queryAudio()", start)
        implementation = source[start:end]

        readback = implementation.index('val destSha256 = readbackDigest.digest()')
        verify = implementation.index('destSha256 != sourceSha256')
        publish = implementation.index('values.put(MediaStore.MediaColumns.IS_PENDING, 0)')
        self.assertLess(readback, verify)
        self.assertLess(verify, publish)
        self.assertIn('context.contentResolver.delete(uri, null, null)', implementation)
        self.assertIn('sourceSha256 = computeSha256(file)', implementation)

    def test_legacy_copy_uses_sha_and_cleans_on_failure(self):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("fun addToMediaStore(")
        end = source.index("fun queryAudio()", start)
        implementation = source[start:end]
        self.assertIn('val verifiedSha256 = computeSha256(target)', implementation)
        self.assertIn('verifiedSha256 != sourceSha256', implementation)
        self.assertIn('target.delete()', implementation)


if __name__ == "__main__":
    unittest.main()
