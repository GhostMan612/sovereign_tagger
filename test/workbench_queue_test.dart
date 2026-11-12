// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
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
  });
}
