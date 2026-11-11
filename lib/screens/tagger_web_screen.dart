// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

/// In-app browser for Tagger's two approved developer consoles.
///
/// Scope honesty, stated plainly because it is easy to overclaim: a page
/// here is still an external website. Its server and any embedded third
/// parties receive the device's IP address and user agent. Keeping the
/// browser closed does not make the site private, and this screen does
/// not claim to block trackers. JavaScript is ON here, unlike the
/// Recovery-for-All screen this was ported from: both approved hosts
/// are authenticated developer consoles that need it to log in and work
/// at all, so JS-off would make the port pointless. The exception is
/// per-host, not global: only genius.com and console.acrcloud.com ever
/// load in this screen, navigation off those hosts is blocked, and
/// there are no JavaScript channels into app state.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TaggerWebScreen extends StatefulWidget {
  final Uri uri;
  final String title;
  final Future<void> Function(Uri uri)? onOpenExternal;

  const TaggerWebScreen({
    super.key,
    required this.uri,
    required this.title,
    this.onOpenExternal,
  });

  @override
  State<TaggerWebScreen> createState() => _TaggerWebScreenState();
}

class _TaggerWebScreenState extends State<TaggerWebScreen> {
  static const Set<String> _approvedHosts = {
    'genius.com',
    'console.acrcloud.com',
  };
  static const int _maximumUriLength = 2048;

  WebViewController? _controller;
  Uri? _currentUri;
  double _progress = 0;
  String _host = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUri = widget.uri;
    _host = widget.uri.host;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _controller = null;
      _currentUri = widget.uri;
      _error = null;
      _progress = 0;
    });

    try {
      final controller = WebViewController();
      if (!mounted) return;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value / 100);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            final uri = Uri.tryParse(url);
            setState(() {
              _progress = 0;
              _error = null;
              _currentUri = uri ?? _currentUri;
              _host = uri?.host ?? '';
            });
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            final uri = Uri.tryParse(url);
            setState(() {
              _progress = 0;
              _currentUri = uri ?? _currentUri;
              _host = uri?.host ?? _host;
            });
            await _refreshNavState();
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) return;
            final description = error.description;
            setState(() => _error = description.trim().isEmpty
                ? 'This page could not be loaded.'
                : description);
          },
          onHttpError: (error) {
            if (!mounted) return;
            final status = error.response?.statusCode;
            if (status != null && status >= 400) {
              setState(() => _error =
                  'The site returned an error (HTTP $status).');
            }
          },
          onNavigationRequest: _decide,
        ),
      );
      await controller.loadRequest(widget.uri);
      if (!mounted) {
        return;
      }
      setState(() {
        _controller = controller;
        _host = widget.uri.host;
      });
      await _refreshNavState();
    } catch (error) {
      debugPrint('Tagger WebView startup failed: $error');
      if (!mounted) return;
      setState(() =>
          _error = 'This page could not be loaded. Check your connection.');
    }
  }

  NavigationDecision _decide(NavigationRequest navigation) {
    final parsed = Uri.tryParse(navigation.url);
    if (parsed == null) {
      _reportBlocked();
      return NavigationDecision.prevent;
    }
    if (!navigation.isMainFrame) return NavigationDecision.navigate;
    final scheme = parsed.scheme.toLowerCase();
    if (scheme == 'tel' || scheme == 'sms' || scheme == 'mailto') {
      _reportBlocked(externalUri: parsed);
      return NavigationDecision.prevent;
    }
    if (_unsafeReason(parsed) != null) {
      _reportBlocked();
      return NavigationDecision.prevent;
    }
    if (parsed.path.toLowerCase().endsWith('.pdf')) {
      _reportBlocked(externalUri: parsed);
      return NavigationDecision.prevent;
    }
    if (!_isApprovedHost(parsed)) {
      _reportBlocked(externalUri: parsed);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  String? _unsafeReason(Uri uri) {
    if (uri.toString().length > _maximumUriLength) {
      return 'This link is too long to open safely.';
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return 'Only secure HTTPS website links can open in the app.';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'Links with embedded account details cannot open in the app.';
    }
    if (uri.host.isEmpty || uri.host.contains('%')) {
      return 'This website address is not valid.';
    }
    if (uri.hasPort && uri.port != 443) {
      return 'This website uses an unsupported network port.';
    }
    final host = uri.host.toLowerCase();
    if (host.contains(':') || RegExp(r'^\d+$').hasMatch(host)) {
      return 'Direct IP-address links cannot open in the app.';
    }
    final segments = host.split('.');
    if (segments.length == 4 &&
        segments.every((segment) {
          final value = int.tryParse(segment);
          return value != null && value >= 0 && value <= 255;
        })) {
      return 'Direct IP-address links cannot open in the app.';
    }
    if (host == 'localhost' ||
        host == 'local' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return 'Local network links cannot open in the app.';
    }
    return null;
  }

  bool _isApprovedHost(Uri uri) {
    if (_unsafeReason(uri) != null) return false;
    final host = uri.host.toLowerCase();
    return _approvedHosts.any(
      (approved) => host == approved || host == 'www.$approved',
    );
  }

  void _reportBlocked({Uri? externalUri}) {
    if (!mounted) return;
    final externalHandler = widget.onOpenExternal;
    final action = externalUri != null && externalHandler != null
        ? SnackBarAction(
            label: 'Review',
            textColor: Colors.cyanAccent,
            onPressed: () => unawaited(externalHandler(externalUri)),
          )
        : null;
    final message = externalUri != null
        ? 'This link goes to ${externalUri.host}, outside the approved in-app sources.'
        : 'That link was not opened.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'ShareTechMono')),
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.cyanAccent),
        ),
        action: action,
      ),
    );
  }

  Future<void> _refreshNavState() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      if (!mounted) return;
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _handleBack() async {
    final controller = _controller;
    try {
      if (controller != null && await controller.canGoBack()) {
        await controller.goBack();
        if (mounted) await _refreshNavState();
        return;
      }
    } catch (_) {
      // A controller that cannot report history must not trap the user:
      // fall through and close the screen instead.
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reload() async {
    try {
      await _controller?.reload();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'This page could not be reloaded.');
      }
    }
  }

  Future<void> _navigateHistory({required bool forward}) async {
    try {
      if (forward) {
        await _controller?.goForward();
      } else {
        await _controller?.goBack();
      }
      await _refreshNavState();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Page navigation is temporarily unavailable.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(
            widget.title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'ShareTechMono',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.cyanAccent,
            ),
          ),
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          actions: [
            IconButton(
              tooltip: 'Reload',
              onPressed: _controller == null ? null : _reload,
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.public, size: 18, color: Colors.white70),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        label:
                            'Current website: ${_host.isEmpty ? widget.uri.host : _host}',
                        excludeSemantics: true,
                        child: Text(
                          _host.isEmpty ? widget.uri.host : _host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'ShareTechMono',
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open in browser',
                      onPressed: widget.onOpenExternal == null
                          ? null
                          : () => unawaited(widget.onOpenExternal!(
                                _currentUri ?? widget.uri,
                              )),
                      icon: const Icon(Icons.open_in_new, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_progress > 0 && _progress < 1)
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.cyanAccent,
                  ),
                  semanticsLabel: 'Page loading progress',
                ),
              Expanded(
                child: _error != null
                    ? SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.public_off,
                                size: 48,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'PAGE UNAVAILABLE',
                                style: TextStyle(
                                  fontFamily: 'ShareTechMono',
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  fontFamily: 'ShareTechMono',
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _load,
                                child: const Text(
                                  'RETRY',
                                  style: TextStyle(
                                    fontFamily: 'ShareTechMono',
                                    color: Colors.cyanAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (_controller == null
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: Colors.cyanAccent,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'OPENING PAGE…',
                                  style: TextStyle(
                                    fontFamily: 'ShareTechMono',
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : WebViewWidget(controller: _controller!)),
              ),
              Material(
                color: Colors.black,
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: _canGoBack
                            ? () => _navigateHistory(forward: false)
                            : null,
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Forward',
                        onPressed: _canGoForward
                            ? () => _navigateHistory(forward: true)
                            : null,
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
