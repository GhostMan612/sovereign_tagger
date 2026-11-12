# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import json


_RUNTIME_UPDATES_DISABLED = (
    "IN-APP PYTHON UPDATES ARE DISABLED FOR DATA SAFETY. "
    "The previous updater deleted the active yt-dlp installation before "
    "verifying a replacement. Install a verified, signed Sovereign Tagger "
    "APK to update pinned Python dependencies."
)


def _blocked_result():
    return json.dumps({
        "status": "blocked",
        "error_code": "UNSAFE_RUNTIME_UPDATE_DISABLED",
        "message": _RUNTIME_UPDATES_DISABLED,
    })


def execute_scorched_earth():
    return _blocked_result()


def update_python_stack():
    return _blocked_result()


def execute_full_scorched_earth():
    return _blocked_result()
