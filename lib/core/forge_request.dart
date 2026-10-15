// =========================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// =========================================================

enum ForgeOrigin { library, picked, grabber, player }

enum ForgeAutoTask {
  none,
  searchMetadata,
  findLyrics,
  acrIdentify,
  fullAutoTagAndLyrics,
}

class ForgeRequest {
  final String path;
  final String? originUri;
  final ForgeOrigin origin;
  final Map<String, String> prefill;
  final String? suggestedFileName;
  final ForgeAutoTask autoTask;

  const ForgeRequest({
    required this.path,
    required this.origin,
    this.originUri,
    this.prefill = const {},
    this.suggestedFileName,
    this.autoTask = ForgeAutoTask.none,
  });
}
