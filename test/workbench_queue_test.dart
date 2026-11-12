// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/ffmpeg_executor.dart';
import 'package:sovereign_tagger/workbench/workbench_models.dart';
import 'package:sovereign_tagger/workbench/workbench_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Workbench Models - MixTrack', () {
    test('initializes with valid path and default parameters', () {
      final track = MixTrack(path: '/storage/music/bass.wav', durationMs: 120000);
      expect(track.path, equals('/storage/music/bass.wav'));
      expect(track.durationMs, equals(120000));
      expect(track.gain, equals(1.0));
      expect(track.pan, equals(0.0));
    });

    test('copyWith creates new instance with updated properties', () {
      final track = MixTrack(path: '/storage/music/drums.flac');
      final updated = track.copyWith(gain: 0.75, pan: -0.5);
      expect(updated.path, equals('/storage/music/drums.flac'));
      expect(updated.gain, equals(0.75));
      expect(updated.pan, equals(-0.5));
    });

    test('rejects empty or whitespace path', () {
      expect(() => MixTrack(path: ''), throwsArgumentError);
      expect(() => MixTrack(path: '   '), throwsArgumentError);
    });

    test('rejects control characters in path', () {
      expect(() => MixTrack(path: '/music/\u0000track.wav'), throwsArgumentError);
      expect(() => MixTrack(path: '/music/\ntrack.wav'), throwsArgumentError);
      expect(() => MixTrack(path: '/music/\rtrack.wav'), throwsArgumentError);
    });

    test('rejects negative gain', () {
      expect(() => MixTrack(path: '/music/track.wav', gain: -0.1), throwsArgumentError);
    });

    test('rejects pan out of bounds', () {
      expect(() => MixTrack(path: '/music/track.wav', pan: -1.01), throwsArgumentError);
      expect(() => MixTrack(path: '/music/track.wav', pan: 1.01), throwsArgumentError);
    });
  });

  group('Workbench Models - DspOperation', () {
    test('allOperations contains 45 operations', () {
      expect(DspOperation.allOperations.length, equals(45));
    });

    test('chainableOperations contains 20 operations', () {
      expect(DspOperation.chainableOperations.length, equals(20));
      for (final op in DspOperation.chainableOperations) {
        expect(DspOperation.allOperations, contains(op));
      }
    });

    test('videoOperations contains 8 operations', () {
      expect(DspOperation.videoOperations.length, equals(8));
      for (final op in DspOperation.videoOperations) {
        expect(DspOperation.allOperations, contains(op));
      }
    });

    test('isBatchable correctly identifies batchable operations', () {
      expect(DspOperation.isBatchable("Normalize Audio (LUFS -14)"), isTrue);
      expect(DspOperation.isBatchable("Convert Format"), isTrue);
      expect(DspOperation.isBatchable("Extract Audio (Video to MP3)"), isTrue);
      expect(DspOperation.isBatchable("Video Scale / Resize"), isTrue);
      expect(DspOperation.isBatchable("Video Rotate / Flip"), isTrue);

      expect(DspOperation.isBatchable("Mux Video + Audio"), isFalse);
      expect(DspOperation.isBatchable("Mix With File"), isFalse);
      expect(DspOperation.isBatchable("Gapless Join (concat)"), isFalse);
      expect(DspOperation.isBatchable("Crossfade Join"), isFalse);
      expect(DspOperation.isBatchable("Sidechain Duck (sidechaincompress)"), isFalse);
      expect(DspOperation.isBatchable("Scan ReplayGain (EBU R128)"), isFalse);
      expect(DspOperation.isBatchable("Split On Silence (silencedetect)"), isFalse);
      expect(DspOperation.isBatchable("Transcribe (Whisper AI)"), isFalse);
    });

    test('isVideoOp correctly classifies video and audio operations', () {
      for (final op in DspOperation.videoOperations) {
        expect(DspOperation.isVideoOp(op), isTrue);
      }
      expect(DspOperation.isVideoOp("Normalize Audio (LUFS -14)"), isFalse);
      expect(DspOperation.isVideoOp("15-Band Equalizer (AutoEq)"), isFalse);
    });

    test('isForensicOp correctly classifies forensic operations', () {
      expect(DspOperation.isForensicOp("Lossless Audio Extract (-c:a copy)"), isTrue);
      expect(DspOperation.isForensicOp("Split Chapters Losslessly (-c copy)"), isTrue);
      expect(DspOperation.isForensicOp("Fake-Lossless & DR Audit"), isTrue);
      expect(DspOperation.isForensicOp("Convert Format"), isFalse);
    });

    test('outputExtension preserves source audio container extension', () {
      expect(DspOperation.outputExtension('/music/song.flac', "Normalize Audio (LUFS -14)"), equals('flac'));
      expect(DspOperation.outputExtension('/music/song.wav', "Parametric EQ"), equals('wav'));
      expect(DspOperation.outputExtension('/music/song.m4a', "Apply Fades"), equals('m4a'));
      expect(DspOperation.outputExtension('/music/song.ogg', "Fold To Mono"), equals('ogg'));
      expect(DspOperation.outputExtension('/music/song.opus', "Trim Silence"), equals('opus'));
      expect(DspOperation.outputExtension('/music/song.mp3', "Limiter"), equals('mp3'));
      expect(DspOperation.outputExtension('/music/song.aiff', "Limiter"), equals('flac'));
    });

    test('outputExtension handles explicit conversions and audio extraction', () {
      expect(DspOperation.outputExtension('/music/song.flac', "Convert Format", targetAudioFormat: 'wav'), equals('wav'));
      expect(DspOperation.outputExtension('/videos/clip.mp4', "Extract Audio (Video to MP3)"), equals('mp3'));
      expect(DspOperation.outputExtension('/videos/clip.mp4', "Extract Audio (Video to M4A)"), equals('m4a'));
      expect(DspOperation.outputExtension('/videos/clip.mp4', "Video Convert (Container)", targetVideoFormat: 'webm'), equals('webm'));
    });

    test('outputExtension preserves video container for video operations', () {
      expect(DspOperation.outputExtension('/videos/clip.mp4', "Video Rotate / Flip"), equals('mp4'));
      expect(DspOperation.outputExtension('/videos/clip.mkv', "Video Scale / Resize"), equals('mkv'));
      expect(DspOperation.outputExtension('/videos/clip.webm', "Video Crop (Center)"), equals('webm'));
      expect(DspOperation.outputExtension('/videos/clip.avi', "Video Rotate / Flip"), equals('mp4'));
    });
  });

  group('Workbench Models - BatchJob', () {
    test('extracts fileName and baseName correctly', () {
      final job = BatchJob(
        id: 'job_01',
        inputPath: '/storage/music/Subterranean_Homesick_Alien.flac',
        operation: 'Normalize Audio (LUFS -14)',
      );
      expect(job.fileName, equals('Subterranean_Homesick_Alien.flac'));
      expect(job.baseName, equals('Subterranean_Homesick_Alien'));
      expect(job.isFinished, isFalse);
      expect(job.isSuccess, isFalse);
      expect(job.summary, equals('PENDING'));
    });

    test('summary reflects running, completed, failed, and skipped states', () {
      final job = BatchJob(
        id: 'job_02',
        inputPath: '/storage/music/song.mp3',
        operation: 'Convert Format',
      );

      job.status = BatchJobStatus.running;
      job.progress = 0.45;
      expect(job.summary, equals('RUNNING (45%)'));

      job.status = BatchJobStatus.completed;
      job.outputUri = 'content://media/external/audio/media/101';
      expect(job.isFinished, isTrue);
      expect(job.isSuccess, isTrue);
      expect(job.summary, equals('OK -> content://media/external/audio/media/101'));

      job.status = BatchJobStatus.failed;
      job.errorMessage = 'rc=1';
      expect(job.isFinished, isTrue);
      expect(job.isSuccess, isFalse);
      expect(job.summary, equals('FAIL: rc=1'));

      job.status = BatchJobStatus.skipped;
      job.errorMessage = 'Not a video file.';
      expect(job.isFinished, isTrue);
      expect(job.isSuccess, isFalse);
      expect(job.summary, equals('SKIP: Not a video file.'));
    });
  });

  group('Workbench Models - MasteringTarget & AudioInspectResult', () {
    test('MasteringTarget presets provide expected targets', () {
      const streaming = MasteringTarget.streaming();
      expect(streaming.targetLufs, equals(-14.0));
      expect(streaming.maxTruePeakDbtp, equals(-1.0));
      expect(streaming.maxLoudnessRangeLu, equals(11.0));
      expect(streaming.mode, equals("TWO-PASS LOUDNORM"));

      const broadcast = MasteringTarget.broadcast();
      expect(broadcast.targetLufs, equals(-23.0));
      expect(broadcast.maxLoudnessRangeLu, equals(7.0));

      const podcast = MasteringTarget.podcast();
      expect(podcast.targetLufs, equals(-16.0));
      expect(podcast.maxLoudnessRangeLu, equals(9.0));

      const dyn = MasteringTarget.dynamicCompression();
      expect(dyn.mode, equals("DYNAMIC (dynaudnorm)"));
    });

    test('AudioInspectResult stores and exposes analysis telemetry', () {
      const result = AudioInspectResult(
        meanVolumeDb: -22.4,
        maxVolumeDb: -1.2,
        headroomDb: 0.2,
        samples: 480000,
        integratedLufs: -14.2,
        truePeakDbtp: -0.9,
        replayGainTrackDb: 0.2,
        replayGainAlbumDb: 0.2,
        silences: [(start: 0.0, end: 1.2), (start: 45.0, end: null)],
        totalSilenceSec: 1.2,
      );
      expect(result.meanVolumeDb, equals(-22.4));
      expect(result.maxVolumeDb, equals(-1.2));
      expect(result.headroomDb, equals(0.2));
      expect(result.samples, equals(480000));
      expect(result.integratedLufs, equals(-14.2));
      expect(result.truePeakDbtp, equals(-0.9));
      expect(result.silences.length, equals(2));
      expect(result.silences[1].end, isNull);
    });
  });

  group('Workbench Queue - State & Lifecycle', () {
    test('initializes empty and allows adding and removing jobs', () {
      final queue = WorkbenchQueue();
      expect(queue.isEmpty, isTrue);
      expect(queue.totalJobs, equals(0));

      queue.addJob('/media/track1.mp3', 'Normalize Audio (LUFS -14)');
      queue.addJob('/media/track2.wav', 'Parametric EQ');
      expect(queue.totalJobs, equals(2));
      expect(queue.jobs[0].inputPath, equals('/media/track1.mp3'));
      expect(queue.jobs[1].inputPath, equals('/media/track2.wav'));

      queue.removeJobAt(0);
      expect(queue.totalJobs, equals(1));
      expect(queue.jobs[0].inputPath, equals('/media/track2.wav'));

      queue.clear();
      expect(queue.isEmpty, isTrue);
    });

    test('addJobs adds multiple files without duplicates', () {
      final queue = WorkbenchQueue();
      queue.addJobs([
        '/media/track1.mp3',
        '/media/track2.flac',
        '/media/track1.mp3',
      ], 'Convert Format');

      expect(queue.totalJobs, equals(2));
      expect(queue.jobs[0].inputPath, equals('/media/track1.mp3'));
      expect(queue.jobs[1].inputPath, equals('/media/track2.flac'));
    });

    test('rejects adding invalid media paths', () {
      final queue = WorkbenchQueue();
      expect(() => queue.addJob('', 'Convert Format'), throwsArgumentError);
      expect(() => queue.addJob('/media/\u0000bad.mp3', 'Convert Format'), throwsArgumentError);
    });

    test('execute on empty queue returns empty message immediately', () async {
      final queue = WorkbenchQueue();
      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async => '',
        getTempDirectory: () async => '/tmp',
        mediaStoreInjector: (out, title) async => null,
        durationProbe: (p) async => null,
        streamProbe: (p) async => {},
      );
      expect(summary, contains('Queue is empty'));
    });

    test('cancel skips remaining jobs and dispatches completion callbacks', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/track1.mp3', 'Convert Format');
      queue.addJob('/media/track2.mp3', 'Convert Format');
      queue.cancel();

      final completedJobs = <BatchJob>[];
      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async => '',
        getTempDirectory: () async => '/tmp',
        mediaStoreInjector: (out, title) async => null,
        durationProbe: (p) async => 1000,
        streamProbe: (p) async => {'audio': 1},
        onJobCompleted: (job, idx, total) {
          completedJobs.add(job);
        },
      );

      expect(completedJobs.length, equals(2));
      expect(queue.jobs[0].status, equals(BatchJobStatus.skipped));
      expect(queue.jobs[0].errorMessage, contains('cancelled'));
      expect(queue.jobs[1].status, equals(BatchJobStatus.skipped));
      expect(summary, contains('2 skipped'));
    });

    test('video operation skips non-video input files cleanly', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/audio_only.mp3', 'Video Scale / Resize');

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async => '',
        getTempDirectory: () async => '/tmp',
        mediaStoreInjector: (out, title) async => null,
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 1, 'video': 0},
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.skipped));
      expect(queue.jobs[0].errorMessage, equals('Not a video file.'));
      expect(summary, contains('1 skipped'));
      expect(summary, contains('NOT A VIDEO FILE'));
    });

    test('format overrides are passed to output extension resolution', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/source.mp3', 'Convert Format');

      String? resolvedOutPath;
      await queue.execute(
        targetAudioFormat: 'wav',
        commandBuilder: (op, input, out, dur) async {
          resolvedOutPath = out;
          throw StateError('probe stop');
        },
        getTempDirectory: () async => '/tmp',
        mediaStoreInjector: (out, title) async => null,
        durationProbe: (p) async => 1000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(resolvedOutPath, isNotNull);
      expect(resolvedOutPath!.endsWith('.wav'), isTrue);
    });

    test('video convert format override resolves target container', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/source.mp4', 'Video Convert (Container)');

      String? resolvedOutPath;
      await queue.execute(
        targetVideoFormat: 'webm',
        commandBuilder: (op, input, out, dur) async {
          resolvedOutPath = out;
          throw StateError('probe stop');
        },
        getTempDirectory: () async => '/tmp',
        mediaStoreInjector: (out, title) async => null,
        durationProbe: (p) async => 1000,
        streamProbe: (p) async => {'video': 1, 'audio': 1},
      );

      expect(resolvedOutPath, isNotNull);
      expect(resolvedOutPath!.endsWith('.webm'), isTrue);
    });

    test('Extract Audio to M4A requires video input but produces audio output', () {
      const op = "Extract Audio (Video to M4A)";
      expect(DspOperation.requiresVideoInput(op), isTrue);
      expect(DspOperation.producesVideoOutput(op), isFalse);
      expect(DspOperation.producesAudioOutput(op), isTrue);
      expect(DspOperation.outputExtension('/media/clip.mp4', op), equals('m4a'));
    });

    test('media store injection failure preserves cache output and reports cache only', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/track.wav', 'Convert Format');

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async {
          File(out).writeAsStringSync('mock audio');
          return '-y -i input.wav out.wav';
        },
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async => (isSuccess: true, returnCode: 0, output: ''),
        mediaStoreInjector: (out, title) async {
          throw Exception('PlatformException: MediaStore failed');
        },
        durationProbe: (p) async => 1000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.completed));
      expect(queue.jobs[0].outputUri, isNotNull);
      expect(File(queue.jobs[0].outputUri!).existsSync(), isTrue);
      expect(summary, contains('CACHE ONLY'));
      try { File(queue.jobs[0].outputUri!).deleteSync(); } catch (_) {}
    });

    test('overall progress is calculated monotonically across batch items', () {
      final progressValues = <double>[];
      const totalJobs = 4;

      for (int i = 0; i < totalJobs; i++) {
        for (double prog = 0.0; prog <= 1.0; prog += 0.25) {
          final overall = ((i + prog) / totalJobs).clamp(0.0, 1.0);
          progressValues.add(overall);
        }
      }

      for (int i = 1; i < progressValues.length; i++) {
        expect(progressValues[i] >= progressValues[i - 1], isTrue);
      }
      expect(progressValues.first, equals(0.0));
      expect(progressValues.last, equals(1.0));
    });

    test('successful batch execution injects media store and tracks monotonic progress', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song1.mp3', 'Normalize Audio (LUFS -14)');
      queue.addJob('/media/song2.flac', 'Normalize Audio (LUFS -14)');

      final overallProgressList = <double>[];
      final injectedTitles = <String>[];

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async => '-y -i $input out',
        getTempDirectory: () async => '/tmp',
        ffmpegRunner: (cmd, {onStatistics}) async => (isSuccess: true, returnCode: 0, output: 'Render complete'),
        mediaStoreInjector: (out, title) async {
          injectedTitles.add(title);
          return 'content://media/external/audio/$title';
        },
        durationProbe: (p) async => 60000,
        streamProbe: (p) async => {'audio': 1},
        onJobProgress: (job, jobProgress, overallProgress) {
          overallProgressList.add(overallProgress);
        },
      );

      expect(queue.jobs.length, equals(2));
      expect(queue.jobs[0].isSuccess, isTrue);
      expect(queue.jobs[1].isSuccess, isTrue);
      expect(injectedTitles.length, equals(2));
      expect(injectedTitles[0], equals('song1_mod'));
      expect(injectedTitles[1], equals('song2_mod'));
      expect(summary, contains('Batch Done: 2/2 OK'));
    });

    test('ffmpeg filter failure records failure and continues remaining jobs', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/bad_filter.mp3', 'AI Denoise (afftdn)');
      queue.addJob('/media/good_track.mp3', 'Convert Format');

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async => '-y -i $input out',
        getTempDirectory: () async => '/tmp',
        ffmpegRunner: (cmd, {onStatistics}) async {
          if (cmd.contains('bad_filter')) {
            return (isSuccess: false, returnCode: 1, output: "No such filter: 'afftdn'");
          }
          return (isSuccess: true, returnCode: 0, output: 'OK');
        },
        mediaStoreInjector: (out, title) async => 'content://media/$title',
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.failed));
      expect(queue.jobs[0].errorMessage, contains("FILTER 'afftdn' UNAVAILABLE"));
      expect(queue.jobs[1].status, equals(BatchJobStatus.completed));
      expect(summary, contains('1/2 OK'));
      expect(summary, contains('1 failed'));
    });

    test('audio op fails if output stream probe reports zero audio streams', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/corrupt.mp3', 'Normalize Audio (LUFS -14)');

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async => '-y -i $input out',
        getTempDirectory: () async => '/tmp',
        ffmpegRunner: (cmd, {onStatistics}) async => (isSuccess: true, returnCode: 0, output: 'Done'),
        mediaStoreInjector: (out, title) async => 'content://media/$title',
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 0},
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.failed));
      expect(queue.jobs[0].errorMessage, equals('NO AUDIO STREAM IN OUTPUT'));
      expect(summary, contains('1 failed'));
    });

    test('Extract Audio to M4A succeeds when input has video and output has audio', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/music_video.mp4', 'Extract Audio (Video to M4A)');

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async => '-y -i $input -vn -c:a aac $out',
        getTempDirectory: () async => '/tmp',
        ffmpegRunner: (cmd, {onStatistics}) async => (isSuccess: true, returnCode: 0, output: 'Done'),
        mediaStoreInjector: (out, title) async => 'content://media/$title',
        durationProbe: (p) async => 120000,
        streamProbe: (p) async {
          if (p.endsWith('.mp4')) {
            return {'video': 1, 'audio': 1};
          }
          return {'audio': 1, 'video': 0};
        },
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.completed));
      expect(queue.jobs[0].isSuccess, isTrue);
      expect(summary, contains('1/1 OK'));
    });

    test('scoped cancellation sets current job description and cancels matching session only', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song.mp3', 'Normalize Audio (LUFS -14)');

      String? capturedDescription;
      await queue.execute(
        commandBuilder: (op, input, out, dur) async => '-y -i input out',
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async {
          capturedDescription = queue.currentJobDescription;
          expect(queue.currentJobDescription, startsWith('workbench_'));
          queue.cancel();
          return (isSuccess: false, returnCode: 255, output: 'interrupted');
        },
        mediaStoreInjector: (out, title) async => 'content://media/$title',
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(capturedDescription, isNotNull);
      expect(capturedDescription!.startsWith('workbench_'), isTrue);
      expect(queue.jobs[0].status, equals(BatchJobStatus.skipped));
      expect(queue.jobs[0].errorMessage, equals('Batch cancelled by user.'));
    });

    test('cancellation at duration probe skips job and aborts before command construction', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song1.mp3', 'Normalize Audio (LUFS -14)');
      queue.addJob('/media/song2.mp3', 'Normalize Audio (LUFS -14)');

      bool commandBuilderCalled = false;
      bool runnerCalled = false;

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async {
          commandBuilderCalled = true;
          return '-y -i input out';
        },
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async {
          runnerCalled = true;
          return (isSuccess: true, returnCode: 0, output: 'OK');
        },
        mediaStoreInjector: (out, title) async => 'content://media/$title',
        durationProbe: (p) async {
          queue.cancel();
          return 5000;
        },
        streamProbe: (p) async => {'audio': 1},
      );

      expect(commandBuilderCalled, isFalse);
      expect(runnerCalled, isFalse);
      expect(queue.jobs[0].status, equals(BatchJobStatus.skipped));
      expect(queue.jobs[1].status, equals(BatchJobStatus.skipped));
      expect(summary, contains('0/2 OK (2 skipped)'));
    });

    test('cancellation at commandBuilder skips job and cleans up staged file', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song1.mp3', 'Normalize Audio (LUFS -14)');

      String? stagedPath;
      bool runnerCalled = false;

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async {
          stagedPath = out;
          File(out).writeAsStringSync('staged data');
          queue.cancel();
          return '-y -i input out';
        },
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async {
          runnerCalled = true;
          return (isSuccess: true, returnCode: 0, output: 'OK');
        },
        mediaStoreInjector: (out, title) async => 'content://media/$title',
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(runnerCalled, isFalse);
      expect(queue.jobs[0].status, equals(BatchJobStatus.skipped));
      expect(stagedPath, isNotNull);
      expect(File(stagedPath!).existsSync(), isFalse);
      expect(summary, contains('1 skipped'));
    });

    test('cancellation during output stream probe deletes staged output and marks skipped', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song1.mp3', 'Normalize Audio (LUFS -14)');

      String? stagedPath;
      bool injectorCalled = false;

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async {
          stagedPath = out;
          return '-y -i input out';
        },
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async {
          File(stagedPath!).writeAsStringSync('rendered audio');
          return (isSuccess: true, returnCode: 0, output: 'OK');
        },
        mediaStoreInjector: (out, title) async {
          injectorCalled = true;
          return 'content://media/$title';
        },
        durationProbe: (p) async => 5000,
        streamProbe: (p) async {
          if (p == stagedPath) {
            queue.cancel();
          }
          return {'audio': 1};
        },
      );

      expect(injectorCalled, isFalse);
      expect(queue.jobs[0].status, equals(BatchJobStatus.skipped));
      expect(File(stagedPath!).existsSync(), isFalse);
      expect(summary, contains('1 skipped'));
    });

    test('mediaStoreInjector returning null marks job completed as CACHE ONLY and preserves staged output on disk', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song.mp3', 'Normalize Audio (LUFS -14)');

      String? stagedPath;

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async {
          stagedPath = out;
          return '-y -i input out';
        },
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async {
          File(stagedPath!).writeAsStringSync('valid audio data');
          return (isSuccess: true, returnCode: 0, output: 'OK');
        },
        mediaStoreInjector: (out, title) async => null,
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.completed));
      expect(queue.jobs[0].outputUri, equals(stagedPath));
      expect(File(stagedPath!).existsSync(), isTrue);
      expect(summary, contains('CACHE ONLY'));
      try { File(stagedPath!).deleteSync(); } catch (_) {}
    });

    test('mediaStoreInjector returning empty or whitespace string preserves staged output on disk', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song.mp3', 'Normalize Audio (LUFS -14)');

      String? stagedPath;

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async {
          stagedPath = out;
          return '-y -i input out';
        },
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async {
          File(stagedPath!).writeAsStringSync('valid audio data');
          return (isSuccess: true, returnCode: 0, output: 'OK');
        },
        mediaStoreInjector: (out, title) async => '   ',
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.completed));
      expect(queue.jobs[0].outputUri, equals(stagedPath));
      expect(File(stagedPath!).existsSync(), isTrue);
      expect(summary, contains('CACHE ONLY'));
      try { File(stagedPath!).deleteSync(); } catch (_) {}
    });

    test('mediaStoreInjector returning valid URI deletes staged output and records content URI', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song.mp3', 'Normalize Audio (LUFS -14)');

      String? stagedPath;

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async {
          stagedPath = out;
          return '-y -i input out';
        },
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async {
          File(stagedPath!).writeAsStringSync('valid audio data');
          return (isSuccess: true, returnCode: 0, output: 'OK');
        },
        mediaStoreInjector: (out, title) async => 'content://media/external/audio/12345',
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.completed));
      expect(queue.jobs[0].outputUri, equals('content://media/external/audio/12345'));
      expect(File(stagedPath!).existsSync(), isFalse);
      expect(summary, contains('OK song.mp3 -> content://media/external/audio/12345'));
    });

    test('empty mediaStore response with missing staged output marks job failed', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song.mp3', 'Normalize Audio (LUFS -14)');

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async => '-y -i input out',
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async =>
            (isSuccess: true, returnCode: 0, output: 'OK'),
        mediaStoreInjector: (out, title) async => null,
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.failed));
      expect(summary, contains('1 failed'));
      expect(summary, contains('OUTPUT MISSING'));
    });

    test('out-of-order statistics events maintain strictly monotonic jobProgress and overallProgress', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/part1.mp3', 'Normalize Audio (LUFS -14)');
      queue.addJob('/media/part2.mp3', 'Normalize Audio (LUFS -14)');

      final perJobProgress = <String, List<double>>{};
      final recordedOverallProgress = <double>[];

      await queue.execute(
        commandBuilder: (op, input, out, dur) async => '-y -i input out',
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async {
          final statsTimes = [1000, 3000, 2000, 4500, 4000, 6000, 5500, 8000, 10000];
          for (final t in statsTimes) {
            onStatistics?.call(Statistics(1, t, t, 1000, 100.0, 1.0, 0, 0.0, 0.0, 0, 0, null));
          }
          return (isSuccess: true, returnCode: 0, output: 'OK');
        },
        mediaStoreInjector: (out, title) async => 'content://media/$title',
        durationProbe: (p) async => 10000,
        streamProbe: (p) async => {'audio': 1},
        onJobProgress: (job, jobProgress, overallProgress) {
          perJobProgress.putIfAbsent(job.id, () => []).add(jobProgress);
          recordedOverallProgress.add(overallProgress);
        },
      );

      expect(perJobProgress.length, equals(2));
      for (final list in perJobProgress.values) {
        expect(list.isNotEmpty, isTrue);
        for (int i = 1; i < list.length; i++) {
          expect(list[i] >= list[i - 1], isTrue);
        }
      }

      expect(recordedOverallProgress.isNotEmpty, isTrue);
      for (int i = 1; i < recordedOverallProgress.length; i++) {
        expect(recordedOverallProgress[i] >= recordedOverallProgress[i - 1], isTrue);
      }
    });

    test('scoped cancellation during beforeExecuteHook aborts before FFmpeg startup', () async {
      final hookCompleter = Completer<void>();
      FFmpegExecutor.beforeExecuteHook = () async {
        await hookCompleter.future;
      };

      try {
        final jobFuture = FFmpegExecutor.execute('-hide_banner', description: 'workbench_test_hook_abort');
        FFmpegExecutor.cancelCurrent(description: 'workbench_test_hook_abort');
        hookCompleter.complete();

        await expectLater(jobFuture, throwsA(isA<StateError>()));
      } finally {
        FFmpegExecutor.beforeExecuteHook = null;
      }
    });

    test('cancelling Workbench description does not cancel unrelated queued task', () async {
      final hookCompleter = Completer<void>();
      FFmpegExecutor.beforeExecuteHook = () async {
        await hookCompleter.future;
      };

      try {
        final unrelatedFuture = FFmpegExecutor.execute('-hide_banner', description: 'forensics_unrelated_job');
        final workbenchFuture = FFmpegExecutor.execute('-hide_banner', description: 'workbench_batch_job');

        FFmpegExecutor.cancelCurrent(description: 'workbench_batch_job');
        FFmpegExecutor.cancelCurrent(description: 'forensics_unrelated_job');
        hookCompleter.complete();

        await expectLater(unrelatedFuture, throwsA(isA<StateError>()));
        await expectLater(workbenchFuture, throwsA(isA<StateError>()));
      } finally {
        FFmpegExecutor.beforeExecuteHook = null;
      }
    });

    test('WorkbenchQueue cancel halts queue when active and skips remaining jobs', () async {
      final queue = WorkbenchQueue();
      queue.addJob('/media/song1.mp3', 'Normalize Audio (LUFS -14)');
      queue.addJob('/media/song2.mp3', 'Normalize Audio (LUFS -14)');

      final summary = await queue.execute(
        commandBuilder: (op, input, out, dur) async => '-y -i input out',
        getTempDirectory: () async => Directory.systemTemp.path,
        ffmpegRunner: (cmd, {onStatistics}) async {
          queue.cancel();
          return (isSuccess: true, returnCode: 0, output: 'OK');
        },
        mediaStoreInjector: (out, title) async => 'content://media/$title',
        durationProbe: (p) async => 5000,
        streamProbe: (p) async => {'audio': 1},
      );

      expect(queue.jobs[0].status, equals(BatchJobStatus.skipped));
      expect(queue.jobs[1].status, equals(BatchJobStatus.skipped));
      expect(summary, contains('2 skipped'));
    });
  });
}
