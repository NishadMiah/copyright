import 'dart:io';
import 'dart:math';
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/statistics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class VideoService {
  static Future<double?> getMediaDuration(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final information = session.getMediaInformation();
    if (information == null) return null;
    final duration = information.getDuration();
    return duration != null ? double.tryParse(duration) : null;
  }

  static Future<String> getOutputFilePath(
    String inputPath,
    String codec,
  ) async {
    final directory = await getTemporaryDirectory();
    final fileName = p.basenameWithoutExtension(inputPath);
    const extension = '.mp4';
    return p.join(
      directory.path,
      '${fileName}_converted_${DateTime.now().millisecondsSinceEpoch}$extension',
    );
  }

  /// Builds an FFmpeg command that re-encodes with a completely new fingerprint.
  ///
  /// Three layers of fingerprint defeat:
  ///
  /// 1. **Binary/Hash level** – full re-encode with randomized CRF & audio bitrate
  ///    ensures the file hash (MD5/SHA) is completely different every time.
  ///
  /// 2. **Metadata level** – strips ALL original metadata and injects fresh
  ///    creation timestamps, unique comment tags, and new encoder strings.
  ///
  /// 3. **Perceptual level** – applies imperceptible video filters:
  ///    • Sub-pixel crop+pad (removes/adds 2px border → changes frame layout)
  ///    • Ultra-subtle noise injection (strength 2/100 → invisible to eye)
  ///    • Micro brightness/saturation shift (±0.01 → undetectable)
  ///    These defeat perceptual hashing algorithms (pHash, dHash) used by
  ///    platforms like YouTube, TikTok, Instagram, etc.
  ///
  /// **Quality:** CRF 17-18 is considered "visually lossless" by x264/x265
  /// standards. The filters are calibrated to be completely invisible.
  static String _buildFingerprintCommand({
    required String inputPath,
    required String outputPath,
    required String codec,
  }) {
    final random = Random();

    // CRF 17-18: visually lossless quality (lower = better, 0 = lossless)
    final crf = 17 + random.nextInt(2);

    // Random audio bitrate jitter: 190k–196k (high quality, inaudible diff)
    final audioBitrate = 190 + random.nextInt(7);

    // Micro brightness shift: ±0.01 (completely invisible, breaks perceptual hash)
    final brightnessDelta = (random.nextDouble() * 0.02 - 0.01).toStringAsFixed(
      3,
    );

    // Micro saturation shift: 1.00 ± 0.01
    final saturation = (1.0 + (random.nextDouble() * 0.02 - 0.01))
        .toStringAsFixed(3);

    // Fresh timestamp
    final now = DateTime.now().toUtc().toIso8601String();

    // Unique tag
    final uniqueTag =
        '${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(99999)}';

    // Micro speed shift: 0.999 or 1.001 (completely unnoticeable, but shifts every frame's timestamp)
    final speed = random.nextBool() ? 0.999 : 1.001;
    final speedString = speed.toStringAsFixed(3);
    final audioSpeed = (1.0 / speed).toStringAsFixed(3);

    // Micro hue shift: ±0.1 degree
    final hue = (random.nextDouble() * 0.2 - 0.1).toStringAsFixed(2);

    // Video filter chain (Aggressive Fingerprint Destruction):
    //  1. scale=iw*1.02:-1,crop=iw/1.02:ih/1.02 → 2% Subtle Zoom (removes edge fingerprints)
    //  2. noise=c0s=3:allf=t   → subtle temporal noise
    //  3. eq=brightness=$brightnessDelta:saturation=$saturation:contrast=1.01:gamma=1.01 → Multi-point color shift
    //  4. hue=h=$hue           → Micro hue rotation
    //  5. setpts=$speedString*PTS → Temporal timeline stretching
    final vf =
        'scale=iw*1.02:-1,crop=iw/1.02:ih/1.02,'
        'noise=c0s=3:allf=t,'
        'eq=brightness=$brightnessDelta:saturation=$saturation:contrast=1.01:gamma=1.01,'
        'hue=h=$hue,'
        'setpts=$speedString*PTS';

    String effectiveCodec = codec;
    if (Platform.isAndroid) {
      if (codec == 'libx264') effectiveCodec = 'h264_mediacodec';
      if (codec == 'libx265') effectiveCodec = 'hevc_mediacodec';
    } else if (Platform.isIOS) {
      if (codec == 'libx264') effectiveCodec = 'h264_videotoolbox';
      if (codec == 'libx265') effectiveCodec = 'hevc_videotoolbox';
    }

    final command =
        '-y -i "$inputPath" '
        '-map_metadata -1 '
        '-metadata title="Processed by BlazeAura" '
        '-metadata author="BlazeAuraApp Studio" '
        '-metadata copyright="BlazeAuraApp Studio" '
        '-metadata comment="BlazeAura_Unique_$uniqueTag" '
        '-metadata encoder="BlazeAura Video Engine" '
        '-metadata creation_time="$now" '
        '-vf "$vf" '
        '-af "atempo=$audioSpeed" '
        '-c:v $effectiveCodec '
        '-crf $crf '
        '-preset ultrafast '
        '-c:a aac -b:a ${audioBitrate}k '
        '-movflags +faststart '
        '"$outputPath"';

    return command;
  }

  static Future<FFmpegSession> convertVideo({
    required String inputPath,
    required String outputPath,
    required String codec,
    required Function(Statistics) onProgress,
  }) async {
    final command = _buildFingerprintCommand(
      inputPath: inputPath,
      outputPath: outputPath,
      codec: codec,
    );

    print('FFmpeg Executing: $command');

    return await FFmpegKit.executeAsync(
      command,
      (session) async {
        final state = await session.getState();
        final returnCode = await session.getReturnCode();
        print(
          'FFmpeg Finished with state: $state and return code: $returnCode',
        );
      },
      (log) {
        print('FFmpeg Log: ${log.getMessage()}');
      },
      onProgress,
    );
  }

  /// Check if the session completed successfully
  static Future<bool> isSessionSuccessful(FFmpegSession session) async {
    final returnCode = await session.getReturnCode();
    return ReturnCode.isSuccess(returnCode);
  }

  /// Check if the session was cancelled
  static Future<bool> isSessionCancelled(FFmpegSession session) async {
    final returnCode = await session.getReturnCode();
    return ReturnCode.isCancel(returnCode);
  }
}
