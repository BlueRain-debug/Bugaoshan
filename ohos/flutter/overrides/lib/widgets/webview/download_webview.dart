import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'notice_webview_scripts.dart';

/// Owns one OH WebView for the lifetime of a page or CAPTCHA window.
class DownloadWebView extends StatefulWidget {
  static const bool isSupported = true;

  const DownloadWebView({
    super.key,
    this.initialUrlRequest,
    this.initialUserScripts,
    this.initialSettings,
    this.onWebViewCreated,
    this.onLoadStart,
    this.onLoadStop,
    this.onReceivedError,
    this.onDownload,
    this.onJsBeforeUnload,
    this.useNativeNoticeTheme = false,
  });

  final URLRequest? initialUrlRequest;
  final UnmodifiableListView<UserScript>? initialUserScripts;
  final InAppWebViewSettings? initialSettings;
  final void Function(InAppWebViewController)? onWebViewCreated;
  final void Function(InAppWebViewController, WebUri?)? onLoadStart;
  final void Function(InAppWebViewController, WebUri?)? onLoadStop;
  final void Function(
    InAppWebViewController,
    WebResourceRequest,
    WebResourceError,
  )?
  onReceivedError;
  final Future<bool> Function(InAppWebViewController, DownloadStartRequest)?
  onDownload;
  final Future<JsBeforeUnloadResponse?> Function(
    InAppWebViewController,
    JsBeforeUnloadRequest,
  )?
  onJsBeforeUnload;
  // ArkWeb AUTO owns notice theme changes without JS or document reloads.
  final bool useNativeNoticeTheme;

  @override
  State<DownloadWebView> createState() => _DownloadWebViewState();
}

class _DownloadWebViewState extends State<DownloadWebView>
    with WidgetsBindingObserver {
  late final InAppWebView _webView;
  InAppWebViewController? _controller;
  Brightness? _brightness;
  Timer? _probeTimer;
  int _probeRevision = 0;
  bool _probePending = false;
  bool _probeRunning = false;
  bool _loading = true;

  String get _label =>
      'view=${_controller?.getViewId()}, '
      'host=${widget.initialUrlRequest?.url?.host ?? 'local'}';

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = widget.initialSettings?.copy() ?? InAppWebViewSettings();
    settings.overScrollMode = OverScrollMode.NEVER;
    // Retain the plugin platform object as well as its native view. Rebuilding
    // the surrounding theme or loading mask must not replace its controller.
    _webView = InAppWebView(
      initialUrlRequest: widget.initialUrlRequest,
      initialUserScripts: widget.initialUserScripts,
      initialSettings: settings,
      onWebViewCreated: (controller) {
        if (!mounted) return;
        _controller = controller;
        AppLog.i('WebView', 'Created $_label');
        widget.onWebViewCreated?.call(controller);
        _queueThemeProbe();
      },
      onLoadStart: (controller, url) {
        if (!mounted) return;
        _loading = true;
        _invalidateProbe();
        widget.onLoadStart?.call(controller, url);
      },
      onLoadStop: (controller, url) {
        if (!mounted) return;
        _loading = false;
        widget.onLoadStop?.call(controller, url);
        _queueThemeProbe();
      },
      onReceivedError: (controller, request, error) {
        if (!mounted) return;
        if (request.isForMainFrame ?? false) _loading = false;
        widget.onReceivedError?.call(controller, request, error);
        _queueThemeProbe();
      },
      onDownloadStartRequest: widget.onDownload == null ? null : _onDownload,
      onJsBeforeUnload: _onBeforeUnload,
      onJsConfirm: (controller, request) async {
        if (!mounted) {
          return JsConfirmResponse(
            handledByClient: true,
            action: JsConfirmResponseAction.CANCEL,
          );
        }
        AppLog.i(
          'WebView',
          'JS confirm requested; empty=${request.message?.trim().isEmpty ?? true}; '
          '$_label',
        );
        return null;
      },
      onRenderProcessUnresponsive: (controller, url) async {
        AppLog.w('WebView', 'Native renderer unresponsive; $_label');
        return null;
      },
      onRenderProcessResponsive: (controller, url) async {
        AppLog.i('WebView', 'Native renderer responsive; $_label');
        return null;
      },
      onRenderProcessGone: (controller, detail) {
        AppLog.e('WebView', 'Native renderer exited: $detail; $_label');
      },
    );
  }

  Future<void> _onDownload(
    InAppWebViewController controller,
    DownloadStartRequest request,
  ) async {
    if (!mounted) return;
    try {
      await widget.onDownload?.call(controller, request);
    } catch (error) {
      AppLog.e('DownloadWebView', 'Download callback failed: $error');
    }
  }

  Future<JsBeforeUnloadResponse?> _onBeforeUnload(
    InAppWebViewController controller,
    JsBeforeUnloadRequest request,
  ) async {
    if (!mounted) {
      return JsBeforeUnloadResponse(
        handledByClient: true,
        action: JsBeforeUnloadResponseAction.CANCEL,
      );
    }
    AppLog.i(
      'WebView',
      'Before-unload requested; empty=${request.message?.trim().isEmpty ?? true}; '
      '$_label',
    );
    try {
      final response = await widget.onJsBeforeUnload?.call(controller, request);
      if (!mounted) {
        return JsBeforeUnloadResponse(
          handledByClient: true,
          action: JsBeforeUnloadResponseAction.CANCEL,
        );
      }
      // Null preserves the plugin's normal confirmation dialog.
      return response;
    } catch (error) {
      AppLog.e('WebView', 'Before-unload callback failed: $error');
      return JsBeforeUnloadResponse(
        handledByClient: true,
        action: JsBeforeUnloadResponseAction.CANCEL,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final previous = _brightness;
    _brightness = brightness;
    if (previous != null && previous != brightness) {
      AppLog.i('WebView', 'Theme changed to ${brightness.name}; $_label');
      _invalidateProbe();
      // Notice CSS responds to ArkWeb's native preferred color scheme.
      // Leave the displayed document and layout loader alone during a toggle.
      _probePending = !widget.useNativeNoticeTheme;
      _queueThemeProbe();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queueThemeProbe();
    } else {
      _invalidateProbe();
      if (_probeRunning) _probePending = true;
    }
  }

  void _invalidateProbe() {
    _probeRevision++;
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  void _queueThemeProbe() {
    if (widget.useNativeNoticeTheme ||
        !mounted ||
        !_foreground ||
        _loading ||
        _controller == null ||
        !_probePending ||
        _probeRunning ||
        _probeTimer != null) {
      return;
    }
    _probeTimer = Timer(const Duration(milliseconds: 350), () {
      _probeTimer = null;
      unawaited(_probeTheme());
    });
  }

  Future<void> _probeTheme() async {
    final controller = _controller;
    if (!mounted || controller == null || !_foreground || _loading) return;
    final revision = _probeRevision;
    final expected = _brightness;
    _probeRunning = true;
    _probePending = false;
    bool isCurrent() =>
        mounted &&
        _foreground &&
        !_loading &&
        revision == _probeRevision &&
        identical(controller, _controller);
    try {
      final state = await controller
          .evaluateJavascript(source: webViewThemeProbeScript(revision))
          .timeout(const Duration(seconds: 2));
      if (!isCurrent()) return;
      AppLog.i(
        'WebView',
        'Theme JS replied; expected=${expected?.name}; state=$state; $_label',
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!isCurrent()) return;
      final frame = await controller
          .evaluateJavascript(source: webViewThemeFrameScript(revision))
          .timeout(const Duration(seconds: 2));
      if (!isCurrent()) return;
      AppLog.i('WebView', 'Theme frame probe: $frame; $_label');
    } catch (error) {
      if (isCurrent()) {
        AppLog.w('WebView', 'Theme probe did not complete: $error; $_label');
      }
    } finally {
      _probeRunning = false;
      _queueThemeProbe();
    }
  }

  @override
  Widget build(BuildContext context) => _webView;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invalidateProbe();
    AppLog.i('WebView', 'Disposed $_label');
    _controller = null;
    // InAppWebView owns controller disposal; never dispose it a second time.
    super.dispose();
  }
}
