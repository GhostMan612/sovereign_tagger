// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_shell.dart';
import 'core/feedback_settings.dart';
import 'core/sfx.dart';
import 'widgets/cyber_ink.dart';
import 'widgets/cyber_page_transitions.dart';
import 'widgets/machine_rain.dart';
import 'widgets/tap_fx_layer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final savedColor = prefs.getInt('accent_color');
  if (savedColor != null) {
    SovereignState.accentColor.value = Color(savedColor);
  }
  await FeedbackSettings.load(prefs);
  Sfx.init();

  runApp(const SovereignApp());
}

class SovereignApp extends StatelessWidget {
  const SovereignApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return MaterialApp(
          title: 'Sovereign Tagger',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: themeColor, brightness: Brightness.dark),
            useMaterial3: true,
            splashFactory: CyberInk.splashFactory,
            pageTransitionsTheme: const PageTransitionsTheme(builders: {
              TargetPlatform.android: CyberPageTransitionsBuilder(),
              TargetPlatform.iOS: CyberPageTransitionsBuilder(),
            }),
          ),
          builder: (context, child) => TapFxLayer(accent: SovereignState.accentColor, child: child ?? const SizedBox.shrink()),
          home: const SplashScreen(),
        );
      }
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.0;
  String _statusText = "INITIATING BOOT SEQUENCE...";

  @override
  void initState() {
    super.initState();
    _bootSequence();
  }

  Future<void> _bootSequence() async {
    await Future.delayed(const Duration(milliseconds: 400));
    
    if (mounted) {
      setState(() {
        _progress = 0.25;
        _statusText = "MOUNTING FFMPEG DSP ENGINE...";
      });
    }
    try {
      await FFmpegKitExtended.initialize();
      final filters = FFmpegKitExtended.getRegisteredFilters();
      debugPrint("FFmpeg armed: ${filters.length} chars of filters registered (full+gpl)");
      final hasWhisper = filters.toLowerCase().contains("whisper");
      debugPrint("WHISPER SURFACE: ${hasWhisper ? "DETECTED in registered filters — wire transcribe op" : "NOT exposed as filter — Phase D needs plugin route"}");
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() {
        _progress = 0.60;
        _statusText = "DECRYPTING STORAGE VAULT...";
      });
    }
    
    try {
      const storageChannel = MethodChannel('com.sovereign.tagger/storage');
      final encryptedData = await storageChannel.invokeMethod('autoImportConfig');
      if (encryptedData != null && encryptedData.toString().isNotEmpty) {
        final decoded = base64Decode(encryptedData.toString());
        final decryptedBytes = decoded.map((b) => b ^ 0x53).toList();
        final jsonStr = utf8.decode(decryptedBytes);
        final config = jsonDecode(jsonStr);
        
        if (mounted) {
          setState(() {
            _progress = 0.85;
            _statusText = "SYNCING KERNEL PREFERENCES...";
          });
        }

        final prefs = await SharedPreferences.getInstance();
        if (config["genius_key"] != null) await prefs.setString('genius_key', config["genius_key"]);
        if (config["acr_host"] != null) await prefs.setString('acr_host', config["acr_host"]);
        if (config["acr_key"] != null) await prefs.setString('acr_key', config["acr_key"]);
        if (config["acr_secret"] != null) await prefs.setString('acr_secret', config["acr_secret"]);
      }
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 400));

    if (mounted) {
      setState(() {
        _progress = 1.0;
        _statusText = "SYSTEM STABLE. ENTERING THE MACHINE.";
      });
    }

    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MainShell(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/splash-screen-bg.png'),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
                  ),
                ),
              ),
              Positioned.fill(child: MachineRain(accentColor: themeColor, opacity: 0.22)),
              Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/app-icon.png',
                      height: 100,
                      width: 100,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Sovereign\nTagger',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 36, 
                        fontWeight: FontWeight.bold, 
                        letterSpacing: 2,
                        shadows: [
                          Shadow(
                            blurRadius: 10.0,
                            color: themeColor,
                            offset: const Offset(0, 0),
                          ),
                        ]
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Native Python Engine\nyt-dlp • FFmpeg\nMetadata Intelligence',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: themeColor, 
                        fontFamily: 'monospace', 
                        fontSize: 14, 
                        height: 1.5
                      ),
                    ),
                    const SizedBox(height: 48),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                      valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                      minHeight: 4,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _statusText,
                            style: TextStyle(
                              color: themeColor, 
                              fontFamily: 'VT323', 
                              fontSize: 16
                            ),
                          ),
                        ),
                        Text(
                          '[ ${(_progress * 100).toInt()}% ]',
                          style: TextStyle(
                            color: themeColor, 
                            fontFamily: 'VT323', 
                            fontSize: 16,
                            fontWeight: FontWeight.bold
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ],
          ),
        );
      }
    );
  }
}