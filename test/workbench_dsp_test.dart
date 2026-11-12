// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/workbench/dsp_builders.dart';
import 'package:sovereign_tagger/workbench/video_dsp_builders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio DSP Builders - Codecs & Filters', () {
    test('buildAudioCodecArgs selects expected encoder and bit depth', () {
      expect(buildAudioCodecArgs('flac', bitDepth: 16), equals('-c:a flac'));
      expect(buildAudioCodecArgs('flac', bitDepth: 24), equals('-c:a flac -sample_fmt s32'));
      expect(buildAudioCodecArgs('wav', bitDepth: 16), equals('-c:a pcm_s16le'));
      expect(buildAudioCodecArgs('wav', bitDepth: 24), equals('-c:a pcm_s24le'));
      expect(buildAudioCodecArgs('m4a'), equals('-c:a aac -b:a 256k'));
      expect(buildAudioCodecArgs('ogg'), equals('-c:a libvorbis -q:a 6'));
      expect(buildAudioCodecArgs('opus'), equals('-c:a libopus -b:a 256k'));
      expect(buildAudioCodecArgs('mp3'), equals('-c:a libmp3lame -b:a 320k'));
      expect(buildAudioCodecArgs('unknown'), equals('-c:a libmp3lame -b:a 320k'));
    });

    test('buildResampleFilter handles Source pass-through and SOXR rates', () {
      expect(buildResampleFilter('Source'), isEmpty);
      expect(buildResampleFilter(''), isEmpty);
      expect(buildResampleFilter('48000'), equals('aresample=48000:resampler=soxr'));
      expect(buildResampleFilter('96000'), equals('aresample=96000:resampler=soxr'));
    });

    test('buildVolumeDetectArgs, silence detect and ebur128 construct valid syntax', () {
      expect(buildVolumeDetectArgs('/path/to/media.flac'), equals('-y -i "/path/to/media.flac" -af volumedetect -f null -'));
      expect(buildSilenceDetectArgs('/path/to/media.wav'), equals('-y -i "/path/to/media.wav" -af silencedetect=noise=-45dB:d=0.3 -f null -'));
      expect(buildSilenceDetectArgs('/path/to/media.wav', noiseDb: -50.0, minDurationSec: 0.5), equals('-y -i "/path/to/media.wav" -af silencedetect=noise=-50dB:d=0.5 -f null -'));
      expect(buildEbuR128Args('/path/to/media.mp3'), equals('-y -i "/path/to/media.mp3" -af ebur128 -f null -'));
    });
  });

  group('Loudnorm Analysis & Filters', () {
    test('buildLoudnormFirstPassArgs formats correct pass 1 JSON probe', () {
      expect(
        buildLoudnormFirstPassArgs('/path/to/input.wav'),
        equals('-y -i "/path/to/input.wav" -af "loudnorm=I=-14:LRA=11:TP=-1.5:print_format=json" -f null -'),
      );
    });

    test('buildLoudnormFilter supports single-pass, dynamic, and two-pass linear modes', () {
      expect(buildLoudnormFilter(), equals('loudnorm=I=-14:LRA=11:TP=-1.5'));
      expect(buildLoudnormFilter(mode: 'DYNAMIC (dynaudnorm)'), equals('dynaudnorm=p=0.9:m=12'));

      final measured = {
        'input_i': '-16.2',
        'input_lra': '8.5',
        'input_tp': '-0.8',
        'input_thresh': '-26.5',
        'target_offset': '0.2',
      };
      final twoPass = buildLoudnormFilter(measured: measured);
      expect(twoPass, contains('measured_I=-16.2'));
      expect(twoPass, contains('measured_LRA=8.5'));
      expect(twoPass, contains('measured_TP=-0.8'));
      expect(twoPass, contains('measured_thresh=-26.5'));
      expect(twoPass, contains('offset=0.2'));
      expect(twoPass, contains('linear=true'));
    });

    test('parseLoudnormMeasurements extracts JSON block from raw output', () {
      const output = '''
[Parsed_loudnorm_0 @ 0x1234]
{
  "input_i" : "-18.52",
  "input_tp" : "-1.20",
  "input_lra" : "9.80",
  "input_thresh" : "-28.70",
  "output_i" : "-14.05",
  "target_offset" : "0.05"
}
[Parsed_loudnorm_0 @ 0x1234] Summary complete.
''';
      final parsed = parseLoudnormMeasurements(output);
      expect(parsed, isNotNull);
      expect(parsed!['input_i'], equals('-18.52'));
      expect(parsed['input_tp'], equals('-1.20'));
      expect(parsed['input_lra'], equals('9.80'));
      expect(parsed['input_thresh'], equals('-28.70'));
      expect(parsed['target_offset'], equals('0.05'));

      expect(parseLoudnormMeasurements('no json here'), isNull);
    });
  });

  group('Silence Detection & Splitting', () {
    test('parseSilences extracts silence starts and ends accurately', () {
      const output = '''
silence_start: 12.345
silence_end: 15.678 | silence_duration: 3.333
silence_start: 45.000
silence_end: 47.500 | silence_duration: 2.500
silence_start: 90.123
''';
      final silences = parseSilences(output);
      expect(silences.length, equals(3));
      expect(silences[0].start, closeTo(12.345, 0.001));
      expect(silences[0].end, closeTo(15.678, 0.001));
      expect(silences[1].start, closeTo(45.000, 0.001));
      expect(silences[1].end, closeTo(47.500, 0.001));
      expect(silences[2].start, closeTo(90.123, 0.001));
      expect(silences[2].end, isNull);
    });

    test('splitSegmentsFromSilence calculates non-silent segments exceeding minimum duration', () {
      const output = '''
silence_start: 10.0
silence_end: 12.0 | silence_duration: 2.0
silence_start: 25.0
silence_end: 27.0 | silence_duration: 2.0
''';
      final segments = splitSegmentsFromSilence(output, 40000, minSegmentSec: 2.0);
      expect(segments.length, equals(3));
      expect(segments[0].start, closeTo(0.0, 0.01));
      expect(segments[0].end, closeTo(10.0, 0.01));
      expect(segments[1].start, closeTo(12.0, 0.01));
      expect(segments[1].end, closeTo(25.0, 0.01));
      expect(segments[2].start, closeTo(27.0, 0.01));
      expect(segments[2].end, closeTo(40.0, 0.01));
    });
  });

  group('Fades, EQ, Speed & Region Deletion', () {
    test('buildFadeFilter generates expected in/out bounds', () {
      final both = buildFadeFilter(fadeInSec: 2.5, fadeOutSec: 3.0, totalDurationSec: 10.0);
      expect(both.length, equals(2));
      expect(both[0], equals('afade=t=in:st=0:d=2.50'));
      expect(both[1], equals('afade=t=out:st=7.00:d=3.00'));

      final none = buildFadeFilter(fadeInSec: 0, fadeOutSec: 0, totalDurationSec: 10.0);
      expect(none, isEmpty);
    });

    test('buildGranularSpeedFilter formats rubberband, atempo, and varispeed', () {
      final rubber = buildGranularSpeedFilter(speed: 1.25, pitchMode: 'RUBBERBAND (pitch only)');
      expect(rubber, equals(['rubberband=pitch=1.25']));

      final atempo = buildGranularSpeedFilter(speed: 1.5, pitchMode: 'ATEMPO (tempo only)');
      expect(atempo, equals(['atempo=1.50']));

      final varispeed = buildGranularSpeedFilter(speed: 0.8, pitchMode: 'VARISPEED (pitch+tempo)');
      expect(varispeed, equals(['asetrate=44100*0.80,aresample=44100']));

      final full = buildGranularSpeedFilter(
        speed: 1.1,
        pitchMode: 'ATEMPO (tempo only)',
        isReversed: true,
        reverbIntensity: 0.5,
      );
      expect(full, contains('areverse'));
      expect(full, contains('atempo=1.10'));
      expect(full, contains('aecho=0.8:0.88:80.0:0.4'));
    });

    test('buildEqFilter and build15BandEqFilter validate band values and throw on all-zero', () {
      expect(() => buildEqFilter(), throwsStateError);
      final eq = buildEqFilter(bass: 3.0, treble: -2.0);
      expect(eq.length, equals(2));
      expect(eq[0], equals('bass=g=3.0:f=100'));
      expect(eq[1], equals('treble=g=-2.0:f=8000'));

      final allZero15 = List.filled(15, 0.0);
      expect(() => build15BandEqFilter(allZero15), throwsStateError);

      final bands15 = List.filled(15, 0.0);
      bands15[0] = 4.0;
      bands15[14] = -3.5;
      final eq15 = build15BandEqFilter(bands15);
      expect(eq15.length, equals(2));
      expect(eq15[0], equals('equalizer=f=25:t=q:w=1.2:g=4.0'));
      expect(eq15[1], equals('equalizer=f=16000:t=q:w=1.2:g=-3.5'));
    });

    test('buildFirequalizerCurve generates gain entries and throws when empty', () {
      expect(() => buildFirequalizerCurve(), throwsStateError);
      final curve = buildFirequalizerCurve(bass: 2.0, treble: 1.5);
      expect(curve, contains("entry(100,2.0)"));
      expect(curve, contains("entry(8000,1.5)"));
    });

    test('buildDeleteRegionFilter validates start < end and formats aselect', () {
      expect(() => buildDeleteRegionFilter(startSec: 10.0, endSec: 5.0), throwsStateError);
      expect(() => buildDeleteRegionFilter(startSec: 10.0, endSec: 10.0), throwsStateError);
      final filter = buildDeleteRegionFilter(startSec: 5.0, endSec: 12.5);
      expect(filter, equals("aselect='not(between(t,5.0,12.5))',asetpts=N/SR/TB"));
    });
  });

  group('Multi-Track Mixing, Sidechain, Joins, Tones & Spectrogram', () {
    test('buildSidechainDuckArgs constructs proper sidechaincompress filter graph', () {
      final cmd = buildSidechainDuckArgs(
        mainPath: '/music.wav',
        sidechainPath: '/voice.wav',
        outPath: '/ducked.flac',
        thresholdDb: -24.0,
        ratio: 6.0,
        attackMs: 150.0,
        releaseMs: 400.0,
        container: 'flac',
      );
      expect(cmd, contains('-i "/music.wav" -i "/voice.wav"'));
      expect(cmd, contains('sidechaincompress=threshold=0.0631:ratio=6.0:attack=150:release=400'));
      expect(cmd, contains('-c:a flac "/ducked.flac"'));
    });

    test('buildCrossfadeJoinArgs and buildGaplessJoinArgs format valid join graphs', () {
      final xfade = buildCrossfadeJoinArgs(
        firstPath: '/a.wav',
        secondPath: '/b.wav',
        outPath: '/joined.wav',
        xfadeSec: 2.5,
        container: 'wav',
      );
      expect(xfade, contains('acrossfade=d=2.50:c1=tri:c2=tri'));
      expect(xfade, contains('-c:a pcm_s16le "/joined.wav"'));

      final gapless = buildGaplessJoinArgs(
        firstPath: '/a.flac',
        secondPath: '/b.flac',
        outPath: '/joined.flac',
        container: 'flac',
      );
      expect(gapless, contains('aresample=48000:ocl=stereo:resampler=soxr[a0]'));
      expect(gapless, contains('concat=n=2:v=0:a=1[out]'));
      expect(gapless, contains('-c:a flac "/joined.flac"'));
    });

    test('buildToneArgs formats sine wave and noise sources', () {
      final sine = buildToneArgs(toneType: 'SINE', freq: 440.0, durationSec: 3.0, outPath: '/tone.wav');
      expect(sine, contains('sine=frequency=440:duration=3.00:sample_rate=48000'));

      final noise = buildToneArgs(toneType: 'WHITE NOISE', freq: 0, durationSec: 2.0, outPath: '/noise.wav');
      expect(noise, contains('anoisesrc=color=white:duration=2.00:sample_rate=48000:amplitude=0.6'));
    });

    test('buildSpectrogramArgs formats showspectrumpic lavfi graph', () {
      final cmd = buildSpectrogramArgs(inputPath: '/audio.flac', outPath: '/spec.png');
      expect(cmd, equals('-y -i "/audio.flac" -lavfi "showspectrumpic=s=1280x720:legend=1" -frames:v 1 "/spec.png"'));
    });

    test('buildMultitrackMixArgs constructs multi-input resample and amix filter complex', () {
      final cmd = buildMultitrackMixArgs(
        inputPaths: ['/track1.wav', '/track2.wav'],
        gains: [1.0, 0.75],
        pans: [0.0, -0.5],
        outPath: '/mixed.mp3',
        container: 'mp3',
      );
      expect(cmd, contains('-i "/track1.wav" -i "/track2.wav"'));
      expect(cmd, contains('[0:a]aresample=48000:ocl=stereo:resampler=soxr,volume=1.00'));
      expect(cmd, contains('[1:a]aresample=48000:ocl=stereo:resampler=soxr,volume=0.75'));
      expect(cmd, contains('amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.95:attack=5:release=50'));
      expect(cmd, contains('-c:a libmp3lame -b:a 320k "/mixed.mp3"'));
    });
  });

  group('Video DSP Builders', () {
    test('buildVideoCodecArgs and buildVideoAudioCodecArgs handle webm and mp4 containers', () {
      expect(buildVideoCodecArgs('mp4'), contains('-c:v libx264'));
      expect(buildVideoCodecArgs('webm'), contains('-c:v libvpx-vp9'));
      expect(buildVideoAudioCodecArgs('mp4'), equals('-c:a aac -b:a 192k'));
      expect(buildVideoAudioCodecArgs('webm'), equals('-c:a libopus -b:a 192k'));
    });

    test('buildVideoRotateFilter builds valid transpose chains', () {
      expect(buildVideoRotateFilter(rotate: 'NONE'), isEmpty);
      expect(buildVideoRotateFilter(rotate: '90 CW'), equals('transpose=1'));
      expect(buildVideoRotateFilter(rotate: '180'), equals('transpose=1,transpose=1'));
      expect(buildVideoRotateFilter(rotate: '90 CCW'), equals('transpose=2'));
      expect(buildVideoRotateFilter(rotate: '90 CW', flipH: true), equals('transpose=1,hflip'));
      expect(buildVideoRotateFilter(rotate: 'NONE', flipH: true, flipV: true), equals('hflip,vflip'));
    });

    test('buildVideoScaleHeight and buildVideoCropFilter match resolution and aspect ratios', () {
      expect(buildVideoScaleHeight('1080p'), equals(1080));
      expect(buildVideoScaleHeight('720p'), equals(720));
      expect(buildVideoScaleHeight('480p'), equals(480));

      expect(buildVideoCropFilter('16:9'), contains('min(iw,ih*16/9)'));
      expect(buildVideoCropFilter('4:3'), contains('min(iw,ih*4/3)'));
      expect(buildVideoCropFilter('1:1'), contains('min(iw,ih)'));
      expect(buildVideoCropFilter('9:16'), contains('min(iw,ih*9/16)'));
    });

    test('buildVideoOpSuffix returns dedicated file suffixes', () {
      expect(buildVideoOpSuffix('Video Trim (Re-Encode)'), equals('_trim'));
      expect(buildVideoOpSuffix('Video Rotate / Flip'), equals('_rot'));
      expect(buildVideoOpSuffix('Video Scale / Resize'), equals('_scale'));
      expect(buildVideoOpSuffix('Video Crop (Center)'), equals('_crop'));
      expect(buildVideoOpSuffix('Mute Video (Drop Audio)'), equals('_mute'));
      expect(buildVideoOpSuffix('Extract Audio (Video to M4A)'), equals('_m4a'));
      expect(buildVideoOpSuffix('Video Convert (Container)'), equals('_conv'));
      expect(buildVideoOpSuffix('Mux Video + Audio'), equals('_mux'));
    });

    test('buildVideoCommand generates valid FFmpeg pipelines for all ops', () {
      final rotCmd = buildVideoCommand(
        op: 'Video Rotate / Flip',
        inputPath: '/in.mp4',
        outPath: '/out.mp4',
        rotate: '90 CW',
      );
      expect(rotCmd, contains('-vf "transpose=1"'));

      expect(
        () => buildVideoCommand(op: 'Video Rotate / Flip', inputPath: '/in.mp4', outPath: '/out.mp4'),
        throwsStateError,
      );

      final scaleCmd = buildVideoCommand(
        op: 'Video Scale / Resize',
        inputPath: '/in.mp4',
        outPath: '/out.mp4',
        scale: '720p',
      );
      expect(scaleCmd, contains('-vf "scale=-2:720"'));

      final cropCmd = buildVideoCommand(
        op: 'Video Crop (Center)',
        inputPath: '/in.mp4',
        outPath: '/out.mp4',
        cropAspect: '1:1',
      );
      expect(cropCmd, contains("crop='min(iw,ih)':'min(iw,ih)'"));

      final muteCmd = buildVideoCommand(op: 'Mute Video (Drop Audio)', inputPath: '/in.mp4', outPath: '/out.mp4');
      expect(muteCmd, equals('-y -i "/in.mp4" -map 0:v:0 -c:v copy "/out.mp4"'));

      final m4aCmd = buildVideoCommand(op: 'Extract Audio (Video to M4A)', inputPath: '/in.mp4', outPath: '/out.m4a');
      expect(m4aCmd, equals('-y -i "/in.mp4" -vn -c:a aac -b:a 256k "/out.m4a"'));

      final convCmd = buildVideoCommand(
        op: 'Video Convert (Container)',
        inputPath: '/in.mp4',
        outPath: '/out.webm',
        targetVideoFormat: 'webm',
      );
      expect(convCmd, contains('-c:v libvpx-vp9'));

      expect(
        () => buildVideoCommand(op: 'Mux Video + Audio', inputPath: '/in.mp4', outPath: '/out.mp4'),
        throwsStateError,
      );
      final muxCmd = buildVideoCommand(
        op: 'Mux Video + Audio',
        inputPath: '/in.mp4',
        outPath: '/out.mp4',
        secondFilePath: '/audio.m4a',
      );
      expect(muxCmd, contains('-i "/in.mp4" -i "/audio.m4a" -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest'));
    });

    test('buildClipVideoArgs generates stream-copy trim commands', () {
      final nonZero = buildClipVideoArgs(
        inputPath: '/in.mp4',
        outPath: '/out.mp4',
        startHms: '00:01:00',
        endHms: '00:02:30',
      );
      expect(nonZero, equals('-y -ss 00:01:00 -i "/in.mp4" -t 00:01:30 -c copy -avoid_negative_ts make_zero "/out.mp4"'));

      final zeroStart = buildClipVideoArgs(
        inputPath: '/in.mp4',
        outPath: '/out.mp4',
        startHms: '00:00:00',
        endHms: '00:00:45',
      );
      expect(zeroStart, equals('-y -i "/in.mp4" -to 00:00:45 -c copy -avoid_negative_ts make_zero "/out.mp4"'));
    });
  });
}
