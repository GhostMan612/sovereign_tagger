// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'embedding_model.dart';
import 'embedding_service.dart';
import 'ffmpeg_executor.dart';

class EmbeddingRuntimeState {
  final bool loaded;
  final bool filesReady;
  final bool isBusy;
  final bool isDownloading;
  final double progress;
  final String statusText;
  final int availRamMb;
  final int totalRamMb;
  final bool lowMemory;
  final int modelBytes;
  final int tokenizerBytes;

  const EmbeddingRuntimeState({
    this.loaded = false,
    this.filesReady = false,
    this.isBusy = false,
    this.isDownloading = false,
    this.progress = 0.0,
    this.statusText = 'Fallback 256-D engine active (0 MB RAM).',
    this.availRamMb = 0,
    this.totalRamMb = 0,
    this.lowMemory = false,
    this.modelBytes = 0,
    this.tokenizerBytes = 0,
  });

  EmbeddingRuntimeState copyWith({
    bool? loaded,
    bool? filesReady,
    bool? isBusy,
    bool? isDownloading,
    double? progress,
    String? statusText,
    int? availRamMb,
    int? totalRamMb,
    bool? lowMemory,
    int? modelBytes,
    int? tokenizerBytes,
  }) {
    return EmbeddingRuntimeState(
      loaded: loaded ?? this.loaded,
      filesReady: filesReady ?? this.filesReady,
      isBusy: isBusy ?? this.isBusy,
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      statusText: statusText ?? this.statusText,
      availRamMb: availRamMb ?? this.availRamMb,
      totalRamMb: totalRamMb ?? this.totalRamMb,
      lowMemory: lowMemory ?? this.lowMemory,
      modelBytes: modelBytes ?? this.modelBytes,
      tokenizerBytes: tokenizerBytes ?? this.tokenizerBytes,
    );
  }
}

class ModelLifecycle {
  ModelLifecycle._();
  static final ModelLifecycle instance = ModelLifecycle._();

  final ValueNotifier<EmbeddingRuntimeState> state =
      ValueNotifier<EmbeddingRuntimeState>(const EmbeddingRuntimeState());

  Timer? _idleTimer;
  bool _hookInstalled = false;

  void ensureInitialized() {
    if (_hookInstalled) return;
    _hookInstalled = true;
    FFmpegExecutor.beforeExecuteHook = _beforeFfmpegJob;
    unawaited(refreshStatus());
  }

  void onChatExpanded() {
    ensureInitialized();
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void onChatCollapsed() {
    _idleTimer?.cancel();
    final cur = state.value;
    if (!cur.loaded) return;
    final delay = (cur.totalRamMb > 0 && cur.totalRamMb < 6144)
        ? const Duration(minutes: 5)
        : const Duration(minutes: 15);
    _idleTimer = Timer(delay, () {
      unawaited(unloadFromRam(reason: 'Idle timeout — freed EmbeddingGemma RAM.'));
    });
  }

  Future<void> _beforeFfmpegJob() async {
    final map = await EmbeddingGemmaService.instance.queryStatus();
    final loaded = map['loaded'] == true;
    if (!loaded) return;
    final availMb = (map['availRamMb'] as num?)?.toInt() ?? 2048;
    final lowMem = map['lowMemory'] == true;
    if (lowMem || availMb < 650) {
      debugPrint('MODEL_LIFECYCLE: free RAM $availMb MB before FFmpeg job — unloading EmbeddingGemma');
      await EmbeddingGemmaService.instance.unloadNativeModel(keepAvailableForLazyReload: true);
      await refreshStatus(overrideMessage: 'Paused native interpreter for FFmpeg DSP ($availMb MB free).');
    }
  }

  Future<void> refreshStatus({String? overrideMessage}) async {
    await EmbeddingModel.tryExtractBundledAssets();
    final map = await EmbeddingGemmaService.instance.queryStatus();
    final loaded = map['loaded'] == true;
    final filesReady = map['filesReady'] == true;
    final availMb = (map['availRamMb'] as num?)?.toInt() ?? 0;
    final totalMb = (map['totalRamMb'] as num?)?.toInt() ?? 0;
    final lowMem = map['lowMemory'] == true;
    final mBytes = (map['modelBytes'] as num?)?.toInt() ?? 0;
    final tBytes = (map['tokenizerBytes'] as num?)?.toInt() ?? 0;
    final lastErr = map['lastError']?.toString() ?? '';

    String msg;
    if (overrideMessage != null && overrideMessage.isNotEmpty) {
      msg = overrideMessage;
    } else if (loaded) {
      msg = 'NATIVE LITERT LOADED (256-D MRL) • RAM $availMb / $totalMb MB free';
    } else if (filesReady) {
      msg = 'WEIGHTS INSTALLED (${(mBytes / (1024 * 1024)).toStringAsFixed(0)} MB) • STANDBY (lazy-loads on query)';
    } else if (lastErr.isNotEmpty) {
      msg = 'ERR: $lastErr';
    } else {
      msg = 'FALLBACK 256-D ENGINE ACTIVE • Download or import EmbeddingGemma (.tflite + tokenizer)';
    }

    state.value = state.value.copyWith(
      loaded: loaded,
      filesReady: filesReady,
      availRamMb: availMb,
      totalRamMb: totalMb,
      lowMemory: lowMem,
      modelBytes: mBytes,
      tokenizerBytes: tBytes,
      statusText: msg,
    );
  }

  Future<bool> downloadAndActivate({String? hfToken}) async {
    if (state.value.isBusy) return false;
    state.value = state.value.copyWith(
      isBusy: true,
      isDownloading: true,
      progress: 0.01,
      statusText: 'Connecting to Hugging Face...',
    );
    try {
      await EmbeddingModel.download(
        hfToken: hfToken,
        onProgress: (stage, prog) {
          state.value = state.value.copyWith(
            isBusy: true,
            isDownloading: true,
            progress: prog.clamp(0.0, 1.0),
            statusText: '$stage (${(prog * 100).round()}%)',
          );
        },
      );
      state.value = state.value.copyWith(
        isDownloading: false,
        progress: 1.0,
        statusText: 'Initializing LiteRT EmbeddingGemma interpreter...',
      );
      await EmbeddingGemmaService.instance.loadNativeModel();
      await refreshStatus(overrideMessage: 'EMBEDDINGGEMMA READY ✓ (LiteRT 256-D MRL active)');
      return true;
    } catch (e) {
      debugPrint('MODEL_LIFECYCLE: downloadAndActivate failed: $e');
      await refreshStatus(overrideMessage: '$e');
      return false;
    } finally {
      state.value = state.value.copyWith(
        isBusy: false,
        isDownloading: false,
        progress: 0.0,
      );
    }
  }

  Future<void> cancelDownload() async {
    await EmbeddingModel.cancelDownload();
  }

  Future<bool> importLocalFile({required String path, required bool isTokenizer}) async {
    if (state.value.isBusy) return false;
    state.value = state.value.copyWith(
      isBusy: true,
      statusText: isTokenizer ? 'Staging SentencePiece tokenizer...' : 'Staging EmbeddingGemma .tflite...',
    );
    try {
      if (isTokenizer) {
        await EmbeddingModel.importLocalTokenizer(path);
      } else {
        await EmbeddingModel.importLocalModel(path);
      }
      final bothReady = await EmbeddingModel.areFilesReady();
      if (bothReady) {
        await EmbeddingGemmaService.instance.loadNativeModel();
        await refreshStatus(overrideMessage: 'LOCAL EMBEDDINGGEMMA LOADED ✓ (LiteRT 256-D MRL active)');
      } else {
        final missing = await EmbeddingModel.isModelPresent()
            ? 'Now import sentencepiece.model to activate.'
            : 'Now import embeddinggemma .tflite to activate.';
        await refreshStatus(overrideMessage: 'Staged ✓ — $missing');
      }
      return true;
    } catch (e) {
      debugPrint('MODEL_LIFECYCLE: importLocalFile failed: $e');
      await refreshStatus(overrideMessage: 'Import failed: $e');
      return false;
    } finally {
      state.value = state.value.copyWith(isBusy: false);
    }
  }

  Future<bool> loadIntoRam() async {
    if (state.value.isBusy) return false;
    state.value = state.value.copyWith(isBusy: true, statusText: 'Loading LiteRT interpreter...');
    try {
      await EmbeddingGemmaService.instance.loadNativeModel();
      await refreshStatus(overrideMessage: 'LITE-RT INTERPRETER ACTIVE ✓');
      return true;
    } catch (e) {
      debugPrint('MODEL_LIFECYCLE: loadIntoRam failed: $e');
      await refreshStatus(overrideMessage: 'Load failed: $e');
      return false;
    } finally {
      state.value = state.value.copyWith(isBusy: false);
    }
  }

  Future<void> unloadFromRam({String? reason}) async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await EmbeddingGemmaService.instance.unloadNativeModel(keepAvailableForLazyReload: true);
    await refreshStatus(overrideMessage: reason ?? 'Interpreter unloaded from RAM (lazy-reload standby).');
  }

  Future<void> deleteWeights() async {
    if (state.value.isBusy) return;
    state.value = state.value.copyWith(isBusy: true, statusText: 'Removing weights...');
    try {
      await EmbeddingGemmaService.instance.unloadNativeModel(keepAvailableForLazyReload: false);
      await EmbeddingModel.deleteInstalledWeights();
      await refreshStatus(overrideMessage: 'Weights deleted. Fallback 256-D engine active.');
    } catch (e) {
      debugPrint('MODEL_LIFECYCLE: deleteWeights failed: $e');
      await refreshStatus(overrideMessage: 'Delete fault: $e');
    } finally {
      state.value = state.value.copyWith(isBusy: false);
    }
  }
}
