import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;

import '../app.dart';

class HumanVerificationResult {
  const HumanVerificationResult({
    required this.cookie,
    required this.html,
    required this.url,
  });

  final String cookie;
  final String html;
  final Uri? url;

  bool get hasCookie => cookie.trim().isNotEmpty;
  bool get hasHtml => html.trim().isNotEmpty;
}

class VerifiedWebViewSession {
  VerifiedWebViewSession();

  win.WebviewController? _windowsController;
  WebViewController? _androidController;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  final List<Completer<void>> _loadWaiters = <Completer<void>>[];
  String _currentUrl = '';
  bool _initialized = false;

  Future<HumanVerificationResult> load(Uri url) async {
    await _ensureInitialized();

    final Completer<void> waiter = Completer<void>();
    _loadWaiters.add(waiter);
    if (Platform.isWindows) {
      await _windowsController?.loadUrl(url.toString());
    } else {
      await _androidController?.loadRequest(url);
    }

    await waiter.future.timeout(const Duration(seconds: 25), onTimeout: () {});
    await Future<void>.delayed(const Duration(milliseconds: 450));

    return HumanVerificationResult(
      cookie: await _readCookie() ?? '',
      html: await _readPageHtml() ?? '',
      url: Uri.tryParse(_currentUrl),
    );
  }

  Future<void> dispose() async {
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _windowsController?.dispose();
    _windowsController = null;
    _androidController = null;
    _initialized = false;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    if (Platform.isWindows) {
      final win.WebviewController controller = win.WebviewController();
      _windowsController = controller;
      await controller.initialize();
      _subscriptions.add(
        controller.url.listen((String url) => _currentUrl = url),
      );
      _subscriptions.add(
        controller.loadingState.listen((win.LoadingState state) {
          if (state != win.LoadingState.loading) {
            _completeLoadWaiters();
          }
        }),
      );
      await controller.setUserAgent(_desktopUserAgent);
      await controller.setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
    } else {
      final WebViewController controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) => _currentUrl = url,
            onPageFinished: (String url) {
              _currentUrl = url;
              _completeLoadWaiters();
            },
          ),
        );
      _androidController = controller;
    }
    _initialized = true;
  }

  void _completeLoadWaiters() {
    final List<Completer<void>> waiters = List<Completer<void>>.from(
      _loadWaiters,
    );
    _loadWaiters.clear();
    for (final Completer<void> waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  Future<String?> _readCookie() async {
    if (Platform.isWindows) {
      final Object? value = await _windowsController?.executeScript(
        'document.cookie',
      );
      return _jsString(value);
    }
    final Object? value = await _androidController
        ?.runJavaScriptReturningResult('document.cookie');
    return _jsString(value);
  }

  Future<String?> _readPageHtml() async {
    const String script =
        'document.documentElement ? document.documentElement.outerHTML : ""';
    if (Platform.isWindows) {
      final Object? value = await _windowsController?.executeScript(script);
      return _jsString(value);
    }
    final Object? value = await _androidController
        ?.runJavaScriptReturningResult(script);
    return _jsString(value);
  }
}

Future<HumanVerificationResult?> showHumanVerificationDialog({
  required BuildContext context,
  required Uri url,
  required String pluginName,
}) {
  return showDialog<HumanVerificationResult>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return _HumanVerificationDialog(url: url, pluginName: pluginName);
    },
  );
}

const String _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

String? _jsString(Object? value) {
  if (value == null) {
    return null;
  }
  final String raw = value.toString();
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded?.toString();
    } on FormatException {
      return raw.substring(1, raw.length - 1);
    }
  }
  return raw;
}

class _HumanVerificationDialog extends StatefulWidget {
  const _HumanVerificationDialog({required this.url, required this.pluginName});

  final Uri url;
  final String pluginName;

  @override
  State<_HumanVerificationDialog> createState() =>
      _HumanVerificationDialogState();
}

class _HumanVerificationDialogState extends State<_HumanVerificationDialog> {
  win.WebviewController? _windowsController;
  WebViewController? _androidController;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _initializing = true;
  bool _loading = true;
  String? _error;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url.toString();
    _initWebView();
  }

  @override
  void dispose() {
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      subscription.cancel();
    }
    _windowsController?.dispose();
    super.dispose();
  }

  Future<void> _initWebView() async {
    try {
      if (Platform.isWindows) {
        final win.WebviewController controller = win.WebviewController();
        _windowsController = controller;
        await controller.initialize();
        _subscriptions.add(
          controller.url.listen((String url) {
            if (mounted) {
              setState(() => _currentUrl = url);
            }
          }),
        );
        _subscriptions.add(
          controller.loadingState.listen((win.LoadingState state) {
            if (mounted) {
              setState(() => _loading = state == win.LoadingState.loading);
            }
          }),
        );
        await controller.setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        );
        await controller.setPopupWindowPolicy(
          win.WebviewPopupWindowPolicy.deny,
        );
        await controller.loadUrl(widget.url.toString());
      } else {
        final WebViewController controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (String url) {
                setState(() {
                  _currentUrl = url;
                  _loading = true;
                });
              },
              onPageFinished: (String url) {
                setState(() {
                  _currentUrl = url;
                  _loading = false;
                });
              },
              onWebResourceError: (WebResourceError error) {
                setState(() => _error = error.description);
              },
            ),
          )
          ..loadRequest(widget.url);
        _androidController = controller;
      }
      if (mounted) {
        setState(() => _initializing = false);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = '${error.code}: ${error.message ?? error.details ?? ''}';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _finish() async {
    final String? cookie = await _readCookie();
    final String? html = await _readPageHtml();
    if (!mounted) {
      return;
    }
    if ((cookie == null || cookie.trim().isEmpty) &&
        (html == null || html.trim().isEmpty)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(appSnack('还没有读到可用 Cookie，请完成验证后再点一次。'));
      return;
    }
    Navigator.of(context).pop(
      HumanVerificationResult(
        cookie: cookie ?? '',
        html: html ?? '',
        url: Uri.tryParse(_currentUrl),
      ),
    );
  }

  Future<String?> _readCookie() async {
    if (Platform.isWindows) {
      final Object? value = await _windowsController?.executeScript(
        'document.cookie',
      );
      return _jsString(value);
    }
    final Object? value = await _androidController
        ?.runJavaScriptReturningResult('document.cookie');
    return _jsString(value);
  }

  Future<String?> _readPageHtml() async {
    const String script =
        'document.documentElement ? document.documentElement.outerHTML : ""';
    if (Platform.isWindows) {
      final Object? value = await _windowsController?.executeScript(script);
      return _jsString(value);
    }
    final Object? value = await _androidController
        ?.runJavaScriptReturningResult(script);
    return _jsString(value);
  }

  String? _jsString(Object? value) {
    if (value == null) {
      return null;
    }
    final String raw = value.toString();
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        final Object? decoded = jsonDecode(raw);
        return decoded?.toString();
      } on FormatException {
        return raw.substring(1, raw.length - 1);
      }
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 760;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 14 : 28),
      backgroundColor: AppTheme.surface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 820),
        child: SizedBox(
          width: compact ? double.infinity : 1040,
          height: compact ? 680 : 760,
          child: Column(
            children: <Widget>[
              _DialogHeader(
                pluginName: widget.pluginName,
                currentUrl: _currentUrl,
                loading: _loading || _initializing,
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(child: _buildBody()),
              _DialogFooter(
                onReload: _reload,
                onOpenDevTools: Platform.isWindows
                    ? () => _windowsController?.openDevTools()
                    : null,
                onFinish: _initializing ? null : _finish,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: SelectableText(
          _error!,
          style: TextStyle(color: AppTheme.text2(context)),
        ),
      );
    }
    if (Platform.isWindows) {
      final win.WebviewController? controller = _windowsController;
      if (controller == null) {
        return const SizedBox.shrink();
      }
      return win.Webview(controller);
    }
    final WebViewController? controller = _androidController;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return WebViewWidget(controller: controller);
  }

  Future<void> _reload() async {
    if (Platform.isWindows) {
      await _windowsController?.reload();
    } else {
      await _androidController?.reload();
    }
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.pluginName,
    required this.currentUrl,
    required this.loading,
    required this.onClose,
  });

  final String pluginName;
  final String currentUrl;
  final bool loading;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border(context))),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.verified_user_rounded, color: AppTheme.accent(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$pluginName 人机验证',
                  style: TextStyle(
                    color: AppTheme.text1(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  currentUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.text3(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }
}

class _DialogFooter extends StatelessWidget {
  const _DialogFooter({
    required this.onReload,
    required this.onOpenDevTools,
    required this.onFinish,
  });

  final VoidCallback onReload;
  final VoidCallback? onOpenDevTools;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border(context))),
      ),
      child: Row(
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: onReload,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('刷新'),
          ),
          if (onOpenDevTools != null) ...<Widget>[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onOpenDevTools,
              icon: const Icon(Icons.developer_mode_rounded),
              label: const Text('DevTools'),
            ),
          ],
          const Spacer(),
          FilledButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.check_rounded),
            label: const Text('我已完成验证'),
          ),
        ],
      ),
    );
  }
}
