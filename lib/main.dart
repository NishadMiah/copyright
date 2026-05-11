import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'video_service.dart';

void main() {
  runApp(const CodecSwitcherApp());
}

class CodecSwitcherApp extends StatelessWidget {
  const CodecSwitcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlazeAura Codec',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          primary: const Color(0xFF7B61FF),
          secondary: const Color(0xFF00E5FF),
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  String? _inputPath;
  String? _outputPath;
  String _selectedCodec = 'libx264';
  double _progress = 0;
  bool _isConverting = false;
  bool _conversionDone = false;
  double? _totalDuration;
  String _status = "Ready to transform";

  final List<Map<String, String>> _codecs = [
    {'name': 'H.264 (AVC)', 'value': 'libx264'},
    {'name': 'H.265 (HEVC)', 'value': 'libx265'},
  ];

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final duration = await VideoService.getMediaDuration(path);
      setState(() {
        _inputPath = path;
        _totalDuration = duration;
        _outputPath = null;
        _progress = 0;
        _conversionDone = false;
        _status = "Video selected";
      });
    }
  }

  Future<void> _convert() async {
    if (_inputPath == null) return;

    final output = await VideoService.getOutputFilePath(
      _inputPath!,
      _selectedCodec,
    );

    setState(() {
      _isConverting = true;
      _outputPath = output;
      _progress = 0;
      _conversionDone = false;
      _status = "Converting & changing fingerprint...";
    });

    try {
      final session = await VideoService.convertVideo(
        inputPath: _inputPath!,
        outputPath: output,
        codec: _selectedCodec,
        onProgress: (stats) {
          if (stats != null && _totalDuration != null && _totalDuration! > 0) {
            final time = stats.getTime();
            if (time > 0) {
              setState(() {
                _progress = (time / (_totalDuration! * 1000)).clamp(0.0, 1.0);
              });
            }
          }
        },
      );

      // Wait for the session to finish
      await Future.delayed(const Duration(milliseconds: 500));
      // Poll until done
      while (true) {
        final rc = await session.getReturnCode();
        if (rc != null) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final success = await VideoService.isSessionSuccessful(session);

      if (!mounted) return;
      setState(() {
        _isConverting = false;
        if (success) {
          _progress = 1.0;
          _conversionDone = true;
          _status = "Done! New fingerprint applied ✓";
        } else {
          _status = "Conversion failed. Try again.";
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConverting = false;
        _status = "Error: $e";
      });
    }
  }

  Future<void> _saveToGallery() async {
    if (_outputPath == null) return;

    if (Platform.isAndroid || Platform.isIOS) {
      PermissionStatus status;
      if (Platform.isAndroid) {
        // Request multiple permissions for maximum compatibility
        final statuses = await [
          Permission.photos,
          Permission.videos,
          Permission.storage,
        ].request();

        status =
            statuses[Permission.videos] ??
            statuses[Permission.photos] ??
            statuses[Permission.storage] ??
            PermissionStatus.denied;
      } else {
        status = await Permission.photos.request();
      }

      if (status.isGranted || status.isLimited) {
        final result = await GallerySaver.saveVideo(_outputPath!);
        if (!mounted) return;
        if (result == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Successfully saved to Gallery!"),
              backgroundColor: const Color(0xFF00E5FF),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Failed to save. Try using 'Share' instead."),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Permission denied. Please enable gallery access."),
          ),
        );
      }
    }
  }

  Future<void> _shareFile() async {
    if (_outputPath == null) return;
    await Share.shareXFiles([XFile(_outputPath!)], text: 'Converted Video');
  }

  void _reset() {
    setState(() {
      _inputPath = null;
      _outputPath = null;
      _progress = 0;
      _isConverting = false;
      _conversionDone = false;
      _status = "Ready to transform";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F0F1E),
                    Color(0xFF1A1A3A),
                    Color(0xFF0F0F1E),
                  ],
                ),
              ),
            ),
          ),
          // Animated background bubbles
          const _BackgroundAnimation(),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF7B61FF), Color(0xFF00E5FF)],
                    ).createShader(bounds),
                    child: Text(
                      "BlazeAura Codec",
                      style: GoogleFonts.outfit(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Re-encode • Strip metadata • New fingerprint",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Main Card
                  Expanded(child: _buildMainCard()),

                  const SizedBox(height: 24),

                  // Action Buttons
                  if (!_isConverting) ...[
                    if (_conversionDone)
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildActionButton(
                                  onPressed: _saveToGallery,
                                  label: "Save Gallery",
                                  icon: Icons.download_rounded,
                                  isPrimary: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildActionButton(
                                  onPressed: _shareFile,
                                  label: "Share",
                                  icon: Icons.share_rounded,
                                  isPrimary: false,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _reset,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text("Convert Another"),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white54,
                            ),
                          ),
                        ],
                      )
                    else
                      _buildActionButton(
                        onPressed: _inputPath == null ? _pickVideo : _convert,
                        label: _inputPath == null
                            ? "Select Video"
                            : "Convert & Rebrand",
                        icon: _inputPath == null
                            ? Icons.video_library_rounded
                            : Icons.transform_rounded,
                        isPrimary: true,
                      ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isConverting)
                _buildProgressUI()
              else if (_inputPath == null)
                _buildEmptyState()
              else
                _buildSelectedState(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF7B61FF).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.add_to_photos_outlined,
            color: Color(0xFF7B61FF),
            size: 40,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "No video selected",
          style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          "Pick a video to re-encode with\na completely new fingerprint",
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSelectedState() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "VIDEO DETAILS",
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF7B61FF),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B61FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.movie_rounded,
                    color: Color(0xFF7B61FF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _inputPath!.split('/').last,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_totalDuration != null)
                        Text(
                          "Duration: ${_totalDuration!.toStringAsFixed(1)}s",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            "TARGET CODEC",
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF7B61FF),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _codecs.map((codec) {
              final isSelected = _selectedCodec == codec['value'];
              return ChoiceChip(
                label: Text(codec['name']!),
                selected: isSelected,
                onSelected: (val) {
                  if (val) setState(() => _selectedCodec = codec['value']!);
                },
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                selectedColor: const Color(0xFF7B61FF).withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: isSelected ? const Color(0xFF7B61FF) : Colors.white60,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF7B61FF)
                        : Colors.transparent,
                  ),
                ),
                showCheckmark: false,
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // Fingerprint info card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.fingerprint_rounded,
                  color: Color(0xFF00E5FF),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Full re-encode: new metadata, new hash, new creation date",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text("Change Video"),
              style: TextButton.styleFrom(foregroundColor: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressUI() {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: CircularProgressIndicator(
                value: _progress,
                strokeWidth: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                color: const Color(0xFF00E5FF),
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              children: [
                Text(
                  "${(_progress * 100).toInt()}%",
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  "encoding",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          _status,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          "Re-encoding video & audio streams\nStripping all original metadata",
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () {
            FFmpegKit.cancel();
            setState(() {
              _isConverting = false;
              _status = "Cancelled";
            });
          },
          icon: const Icon(Icons.close, size: 18),
          label: const Text("Cancel"),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
    required bool isPrimary,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isPrimary
            ? const LinearGradient(
                colors: [Color(0xFF7B61FF), Color(0xFF9E8AFF)],
              )
            : null,
        color: isPrimary ? null : Colors.white.withValues(alpha: 0.05),
        border: isPrimary
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: isPrimary
            ? [
                BoxShadow(
                  color: const Color(0xFF7B61FF).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ]
            : [],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}

// ─── Background Animation ──────────────────────────────────────────────────────

class _BackgroundAnimation extends StatefulWidget {
  const _BackgroundAnimation();

  @override
  State<_BackgroundAnimation> createState() => _BackgroundAnimationState();
}

class _BackgroundAnimationState extends State<_BackgroundAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned(
              top: 80 + 60 * _controller.value,
              left: 30 + 40 * (1 - _controller.value),
              child: _Bubble(
                size: 200,
                color: const Color(0xFF7B61FF).withValues(alpha: 0.08),
              ),
            ),
            Positioned(
              bottom: 120 + 50 * (1 - _controller.value),
              right: 20 + 60 * _controller.value,
              child: _Bubble(
                size: 160,
                color: const Color(0xFF00E5FF).withValues(alpha: 0.06),
              ),
            ),
            Positioned(
              top: 300 + 30 * _controller.value,
              right: 80 + 40 * (1 - _controller.value),
              child: _Bubble(
                size: 100,
                color: const Color(0xFF9E8AFF).withValues(alpha: 0.07),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final double size;
  final Color color;

  const _Bubble({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
