// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import '../core/ffmpeg_executor.dart';
import 'dsp_builders.dart';
import 'video_dsp_builders.dart';
import 'workbench_models.dart';

class WorkbenchQueue {
  final List<BatchJob> _jobs = [];
  bool _isRunning = false;
  bool _isCancelled = false;
  int _currentIndex = 0;
  String? _currentJobDescription;
  double _maxReportedOverall = 0.0;

  List<BatchJob> get jobs => List.unmodifiable(_jobs);
  bool get isRunning => _isRunning;
  bool get isCancelled => _isCancelled;
  int get currentIndex => _currentIndex;
  int get totalJobs => _jobs.length;
  bool get isEmpty => _jobs.isEmpty;
  bool get isNotEmpty => _jobs.isNotEmpty;
  String? get currentJobDescription => _currentJobDescription;
  double get maxReportedOverall => _maxReportedOverall;

  void addJob(String inputPath, String operation) {
    if (_isRunning) {
      throw StateError('ERR: Cannot add jobs while queue is running.');
    }
    validateMediaPath(inputPath, name: 'batch input media path');
    final id = 'job_${DateTime.now().microsecondsSinceEpoch}_${_jobs.length}';
    _jobs.add(BatchJob(id: id, inputPath: inputPath, operation: operation));
  }

  void addJobs(List<String> paths, String operation) {
    for (final p in paths) {
      if (!_jobs.any((j) => j.inputPath == p)) {
        addJob(p, operation);
      }
    }
  }

  void removeJobAt(int index) {
    if (_isRunning) {
      throw StateError('ERR: Cannot remove jobs while queue is running.');
    }
    if (index >= 0 && index < _jobs.length) {
      _jobs.removeAt(index);
    }
  }

  void clear() {
    if (_isRunning) {
      throw StateError('ERR: Cannot clear queue while running.');
    }
    _jobs.clear();
    _currentIndex = 0;
    _isCancelled = false;
    _currentJobDescription = null;
    _maxReportedOverall = 0.0;
  }

  void cancel() {
    _isCancelled = true;
    final desc = _currentJobDescription;
    if (desc != null) {
      FFmpegExecutor.cancelCurrent(description: desc);
    }
  }

  Future<String> execute({
    required Future<String> Function(String op, String inputPath, String outPath, int? durationMs) commandBuilder,
    required Future<String> Function() getTempDirectory,
    required Future<String?> Function(String outPath, String title) mediaStoreInjector,
    required Future<int?> Function(String path) durationProbe,
    required Future<Map<String, int>> Function(String path) streamProbe,
    String targetAudioFormat = 'mp3',
    String targetVideoFormat = 'mp4',
    Future<({bool isSuccess, int returnCode, String output})> Function(
      String command, {
      void Function(Statistics stats)? onStatistics,
    })? ffmpegRunner,
    void Function(BatchJob job, int index, int total)? onJobStarted,
    void Function(BatchJob job, double jobProgress, double overallProgress)? onJobProgress,
    void Function(BatchJob job, int index, int total)? onJobCompleted,
  }) async {
    if (_isRunning) {
      throw StateError('ERR: Batch queue is already executing.');
    }
    if (_jobs.isEmpty) {
      return 'Queue is empty — nothing to execute.';
    }

    _isRunning = true;
    _currentIndex = 0;
    _maxReportedOverall = 0.0;

    final lines = <String>[];
    int okCount = 0;
    int failCount = 0;
    int skipCount = 0;

    try {
      final tempDir = await getTempDirectory();

      for (int i = 0; i < _jobs.length; i++) {
        _currentIndex = i;
        final job = _jobs[i];

        bool handleCancellationIfRequested(String? stagedToDelete) {
          if (!_isCancelled) return false;
          job.status = BatchJobStatus.skipped;
          job.errorMessage = 'Batch cancelled by user.';
          job.completedAt = DateTime.now();
          skipCount++;
          lines.add("SKIP ${job.fileName}: CANCELLED");
          if (stagedToDelete != null && stagedToDelete.isNotEmpty) {
            try {
              final f = File(stagedToDelete);
              if (f.existsSync()) f.deleteSync();
            } catch (_) {}
          }
          final stepOverall = ((i + 1) / _jobs.length).clamp(0.0, 1.0);
          if (stepOverall > _maxReportedOverall) {
            _maxReportedOverall = stepOverall;
          }
          onJobCompleted?.call(job, i + 1, _jobs.length);
          return true;
        }

        if (handleCancellationIfRequested(null)) continue;

        job.status = BatchJobStatus.running;
        job.progress = 0.0;
        job.startedAt = DateTime.now();
        onJobStarted?.call(job, i + 1, _jobs.length);

        String? stagedOutPath;

        try {
          final dur = await durationProbe(job.inputPath);
          if (handleCancellationIfRequested(null)) continue;

          if (DspOperation.requiresVideoInput(job.operation)) {
            final inStreams = await streamProbe(job.inputPath);
            if (handleCancellationIfRequested(null)) continue;
            if ((inStreams['video'] ?? 0) == 0) {
              job.status = BatchJobStatus.skipped;
              job.errorMessage = 'Not a video file.';
              job.completedAt = DateTime.now();
              skipCount++;
              lines.add("SKIP ${job.fileName}: NOT A VIDEO FILE");
              final stepOverall = ((i + 1) / _jobs.length).clamp(0.0, 1.0);
              if (stepOverall > _maxReportedOverall) {
                _maxReportedOverall = stepOverall;
              }
              onJobCompleted?.call(job, i + 1, _jobs.length);
              continue;
            }
          }

          final ext = DspOperation.outputExtension(
            job.inputPath,
            job.operation,
            targetAudioFormat: targetAudioFormat,
            targetVideoFormat: targetVideoFormat,
          );
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final outPath = "$tempDir/workbench_batch_${timestamp}_$i.$ext";
          stagedOutPath = outPath;

          final command = await commandBuilder(job.operation, job.inputPath, outPath, dur);
          if (handleCancellationIfRequested(stagedOutPath)) continue;

          final jobDesc = "workbench_${job.id}";
          _currentJobDescription = jobDesc;
          if (handleCancellationIfRequested(stagedOutPath)) continue;

          final bool isSuccess;
          final int retCode;
          final String output;

          void handleStats(Statistics stats) {
            if (dur != null && dur > 0) {
              final prog = (stats.time / dur).clamp(0.0, 1.0);
              if (prog > job.progress) {
                job.progress = prog;
              }
              final calculated = ((i + job.progress) / _jobs.length).clamp(0.0, 1.0);
              if (calculated > _maxReportedOverall) {
                _maxReportedOverall = calculated;
              }
              onJobProgress?.call(job, job.progress, _maxReportedOverall);
            }
          }

          if (ffmpegRunner != null) {
            final res = await ffmpegRunner(
              command,
              onStatistics: handleStats,
            );
            isSuccess = res.isSuccess;
            retCode = res.returnCode;
            output = res.output;
          } else {
            final session = await FFmpegExecutor.execute(
              command,
              durationMs: dur,
              onStatistics: handleStats,
              description: jobDesc,
            );
            isSuccess = ReturnCode.isSuccess(session.getReturnCode());
            retCode = session.getReturnCode();
            output = session.getOutput() ?? "";
          }

          _currentJobDescription = null;
          if (handleCancellationIfRequested(stagedOutPath)) continue;

          if (!isSuccess) {
            if (_isCancelled) {
              handleCancellationIfRequested(stagedOutPath);
              continue;
            }
            final fault = _detectFilterFault(output);
            final err = fault != null
                ? "FILTER '$fault' UNAVAILABLE IN THIS BUILD"
                : "rc=$retCode";
            job.status = BatchJobStatus.failed;
            job.errorMessage = err;
            job.completedAt = DateTime.now();
            failCount++;
            lines.add("FAIL ${job.fileName}: $err");
            try {
              final f = File(outPath);
              if (f.existsSync()) f.deleteSync();
            } catch (_) {}
            final stepOverall = ((i + 1) / _jobs.length).clamp(0.0, 1.0);
            if (stepOverall > _maxReportedOverall) {
              _maxReportedOverall = stepOverall;
            }
            onJobCompleted?.call(job, i + 1, _jobs.length);
            continue;
          }

          final outStreams = await streamProbe(outPath);
          if (handleCancellationIfRequested(stagedOutPath)) continue;

          if (DspOperation.producesVideoOutput(job.operation)) {
            if ((outStreams['video'] ?? 0) == 0) {
              job.status = BatchJobStatus.failed;
              job.errorMessage = 'NO VIDEO STREAM IN OUTPUT';
              job.completedAt = DateTime.now();
              failCount++;
              lines.add("FAIL ${job.fileName}: NO VIDEO STREAM IN OUTPUT");
              try {
                final f = File(outPath);
                if (f.existsSync()) f.deleteSync();
              } catch (_) {}
              final stepOverall = ((i + 1) / _jobs.length).clamp(0.0, 1.0);
              if (stepOverall > _maxReportedOverall) {
                _maxReportedOverall = stepOverall;
              }
              onJobCompleted?.call(job, i + 1, _jobs.length);
              continue;
            }
          } else {
            if ((outStreams['audio'] ?? 0) == 0) {
              job.status = BatchJobStatus.failed;
              job.errorMessage = 'NO AUDIO STREAM IN OUTPUT';
              job.completedAt = DateTime.now();
              failCount++;
              lines.add("FAIL ${job.fileName}: NO AUDIO STREAM IN OUTPUT");
              try {
                final f = File(outPath);
                if (f.existsSync()) f.deleteSync();
              } catch (_) {}
              final stepOverall = ((i + 1) / _jobs.length).clamp(0.0, 1.0);
              if (stepOverall > _maxReportedOverall) {
                _maxReportedOverall = stepOverall;
              }
              onJobCompleted?.call(job, i + 1, _jobs.length);
              continue;
            }
          }

          final titleSuffix = DspOperation.producesVideoOutput(job.operation)
              ? buildVideoOpSuffix(job.operation)
              : (job.operation == "Extract Audio (Video to M4A)" ? "_m4a" : "_mod");
          final title = "${job.baseName}$titleSuffix";

          if (handleCancellationIfRequested(stagedOutPath)) continue;

          try {
            final uriString = await mediaStoreInjector(outPath, title);
            final trimmed = uriString?.trim();
            if (trimmed != null && trimmed.isNotEmpty) {
              job.status = BatchJobStatus.completed;
              job.progress = 1.0;
              job.outputUri = trimmed;
              job.completedAt = DateTime.now();
              okCount++;
              lines.add("OK ${job.fileName} -> $trimmed");
              try {
                final f = File(outPath);
                if (f.existsSync()) f.deleteSync();
              } catch (_) {}
            } else {
              if (File(outPath).existsSync()) {
                job.status = BatchJobStatus.completed;
                job.progress = 1.0;
                job.outputUri = outPath;
                job.completedAt = DateTime.now();
                okCount++;
                lines.add("CACHE ONLY ${job.fileName}: $outPath");
              } else {
                job.status = BatchJobStatus.failed;
                job.errorMessage = 'Output missing from cache after empty MediaStore response';
                job.completedAt = DateTime.now();
                failCount++;
                lines.add("FAIL ${job.fileName}: OUTPUT MISSING");
              }
            }
          } catch (injectErr) {
            if (File(outPath).existsSync()) {
              job.status = BatchJobStatus.completed;
              job.progress = 1.0;
              job.outputUri = outPath;
              job.completedAt = DateTime.now();
              okCount++;
              lines.add("CACHE ONLY ${job.fileName}: $outPath");
            } else {
              job.status = BatchJobStatus.failed;
              job.errorMessage = injectErr.toString();
              job.completedAt = DateTime.now();
              failCount++;
              lines.add("FAIL ${job.fileName}: $injectErr");
            }
          }

          final stepOverall = ((i + 1) / _jobs.length).clamp(0.0, 1.0);
          if (stepOverall > _maxReportedOverall) {
            _maxReportedOverall = stepOverall;
          }
          onJobCompleted?.call(job, i + 1, _jobs.length);
        } on StateError catch (se) {
          if (_isCancelled) {
            handleCancellationIfRequested(stagedOutPath);
          } else {
            job.status = BatchJobStatus.skipped;
            job.errorMessage = se.message;
            job.completedAt = DateTime.now();
            skipCount++;
            lines.add("SKIP ${job.fileName}: ${se.message}");
            final stepOverall = ((i + 1) / _jobs.length).clamp(0.0, 1.0);
            if (stepOverall > _maxReportedOverall) {
              _maxReportedOverall = stepOverall;
            }
            onJobCompleted?.call(job, i + 1, _jobs.length);
          }
        } catch (e) {
          if (_isCancelled) {
            handleCancellationIfRequested(stagedOutPath);
          } else {
            job.status = BatchJobStatus.failed;
            job.errorMessage = e.toString();
            job.completedAt = DateTime.now();
            failCount++;
            lines.add("FAIL ${job.fileName}: $e");
            final stepOverall = ((i + 1) / _jobs.length).clamp(0.0, 1.0);
            if (stepOverall > _maxReportedOverall) {
              _maxReportedOverall = stepOverall;
            }
            onJobCompleted?.call(job, i + 1, _jobs.length);
          }
        } finally {
          _currentJobDescription = null;
          if (stagedOutPath != null &&
              job.outputUri != stagedOutPath &&
              File(stagedOutPath).existsSync()) {
            try { File(stagedOutPath).deleteSync(); } catch (_) {}
          }
        }
      }
    } finally {
      _isRunning = false;
      _isCancelled = false;
      _currentJobDescription = null;
    }

    return "Batch Done: $okCount/${_jobs.length} OK"
        "${skipCount > 0 ? ' ($skipCount skipped)' : ''}"
        "${failCount > 0 ? ' ($failCount failed)' : ''}.\n"
        "${lines.join('\n')}";
  }

  String? _detectFilterFault(String output) {
    final noSuch = RegExp(r"No such filter:\s*'([^']+)'").firstMatch(output);
    if (noSuch != null) return noSuch.group(1);
    final unknown = RegExp(r"Unknown filter\s*'([^']+)'").firstMatch(output);
    if (unknown != null) return unknown.group(1);
    return null;
  }
}
