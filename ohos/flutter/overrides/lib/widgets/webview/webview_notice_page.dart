import 'dart:collection';

import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/pages/campus/downloads/shared_notice_downloads.dart';
import 'package:bugaoshan/providers/app_config_provider.dart';
import 'package:bugaoshan/widgets/dialog/dialog.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/widgets/route/router_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'download_webview.dart';
import 'package:url_launcher/url_launcher.dart';

import 'download_options.dart';
import 'notice_layout_ready.dart';
import 'notice_webview_scripts.dart';
import 'tuanwei_notice_loader.dart';
import 'webview_notice_handlers.dart';
import 'webview_unsupported_page.dart';

export 'download_options.dart';
export 'webview_unsupported_page.dart';

/// Shared WebView-based notice page used by party/XGB and tuanwei/Youth SCU.
class WebViewNoticePage extends StatefulWidget {
  const WebViewNoticePage({
    super.key,
    required this.url,
    required this.beautifyAsset,
    required this.title,
    required this.heroTag,
    required this.debugLabel,
    this.downloadOptions,
    this.enableLoadingMask = true,
  });

  final String url;
  final String? beautifyAsset;
  final String title;
  final String heroTag;
  final String debugLabel;
  final DownloadOptions? downloadOptions;
  final bool enableLoadingMask;

  @override
  State<WebViewNoticePage> createState() => _WebViewNoticePageState();
}

class _WebViewNoticePageState extends State<WebViewNoticePage>
    with WebViewNoticeHandlers {
  InAppWebViewController? _controller;
  String _beautifyScript = '';
  String _domReadyScript = '';
  TuanweiNoticeLoader? _tuanweiLoader;
  NoticeLayoutLoader? _otherNoticeLoader;
  NoticeLayoutLoader? get _layoutLoader => _tuanweiLoader ?? _otherNoticeLoader;
  bool _realLoading = false;
  //disable loading if beautify script is empty
  bool get _loading =>
      _layoutLoader?.isLoading ??
      (_beautifyScript.isNotEmpty && _realLoading && widget.enableLoadingMask);
  set _loading(bool value) {
    if (_beautifyScript.isNotEmpty) _realLoading = value;
  }

  bool _canGoBack = false;
  bool _canGoForward = false;
  List<AttachItem> _pageAttachments = [];
  String _errorHtmlTemplate = '';

  bool get _isCampusNotice => const <String>{
    'assets/js/jwc_notice_beautify.js',
    'assets/js/party_notice_beautify.js',
    'assets/js/tuanwei_notice_beautify.js',
  }.contains(widget.beautifyAsset);

  @override
  InAppWebViewController? get controller => _controller;

  @override
  String get debugLabel => widget.debugLabel;

  @override
  DownloadOptions? get downloadOptions => widget.downloadOptions;

  @override
  List<AttachItem> get pageAttachments => _pageAttachments;

  @override
  set pageAttachments(List<AttachItem> value) => _pageAttachments = value;

  @override
  void initState() {
    super.initState();
    if (widget.beautifyAsset == 'assets/js/tuanwei_notice_beautify.js' &&
        Uri.tryParse(widget.url)?.host == 'tuanwei.scu.edu.cn') {
      _tuanweiLoader = TuanweiNoticeLoader(
        loadScript: () => rootBundle.loadString(widget.beautifyAsset!),
      )..addListener(_onTuanweiLoadingChanged);
      return;
    }
    if (_isCampusNotice) {
      _otherNoticeLoader = NoticeLayoutLoader(
        loadScript: () async => withNoticeSearchTheme(
          await rootBundle.loadString(widget.beautifyAsset!),
          widget.beautifyAsset,
        ),
        buildScript: ({required beautifyScript, required url, required loadId}) =>
            noticeLayoutScript(
              beautifyScript: beautifyScript,
              asset: widget.beautifyAsset!,
              url: url,
              loadId: loadId,
            ),
        readyProbe: noticeLayoutReadyProbe,
      )..addListener(_onTuanweiLoadingChanged);
      return;
    }
    rootBundle.loadString('assets/webview_error.html').then((s) {
      _errorHtmlTemplate = s;
    });
    if (widget.beautifyAsset == null) return;
    rootBundle.loadString(widget.beautifyAsset!).then((s) {
      if (mounted) {
        setState(() {
          _beautifyScript = withNoticeSearchTheme(s, widget.beautifyAsset);
        });
      }
    });
    rootBundle.loadString('assets/js/dom_ready.js').then((s) {
      _domReadyScript = s;
    });
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: 'AttachmentsChannel',
      callback: onAttachmentsMessage,
    );
    controller.addJavaScriptHandler(
      handlerName: 'DOMReady',
      callback: _onDomReady,
    );
    if (widget.downloadOptions != null) {
      controller.addJavaScriptHandler(
        handlerName: 'DownloadAttachment',
        callback: onDownloadAttachment,
      );
    }
    controller.addJavaScriptHandler(
      handlerName: 'OpenImage',
      callback: onOpenImage,
    );
    controller.addJavaScriptHandler(
      handlerName: 'OpenExternalLink',
      callback: onOpenExternalLink,
    );
  }

  Future<JsBeforeUnloadResponse?> _onTuanweiBeforeUnload(
    InAppWebViewController controller,
    JsBeforeUnloadRequest request,
  ) async {
    if (!mounted) {
      return JsBeforeUnloadResponse(
        handledByClient: true,
        action: JsBeforeUnloadResponseAction.CANCEL,
      );
    }
    if (_tuanweiLoader == null ||
        request.url?.host != 'tuanwei.scu.edu.cn' ||
        (request.message?.trim().isNotEmpty ?? false)) {
      return null;
    }
    AppLog.i('TuanweiNotice', 'Allowed empty before-unload confirmation');
    return JsBeforeUnloadResponse(
      handledByClient: true,
      action: JsBeforeUnloadResponseAction.CONFIRM,
    );
  }

  void _onTuanweiLoadingChanged() {
    if (!mounted) return;
    setState(() {
      if (_layoutLoader!.isLoading) _pageAttachments = [];
    });
  }

  void _startNoticeNavigation() {
    if (!mounted) return;
    final loader = _layoutLoader;
    if (loader != null) {
      loader.start();
    } else {
      setState(() {
        _loading = true;
        _pageAttachments = [];
      });
    }
  }

  Future<void> _onLoadStart(InAppWebViewController controller, Uri? url) async {
    _startNoticeNavigation();
  }

  Future<void> _finishLoading({int? tuanweiLoadId}) async {
    bool isCurrent() =>
        mounted &&
        (tuanweiLoadId == null || tuanweiLoadId == _layoutLoader?.generation);
    if (!isCurrent()) return;
    await Future.delayed(const Duration(milliseconds: 50));
    final ctrl = _controller;
    if (ctrl == null || !isCurrent()) return;
    final back = await ctrl.canGoBack();
    final forward = await ctrl.canGoForward();
    if (!isCurrent()) return;
    setState(() {
      _loading = false;
      _canGoBack = back;
      _canGoForward = forward;
    });
  }

  Future<void> _onLoadStop(InAppWebViewController controller, Uri? url) async {
    final loader = _layoutLoader;
    if (loader != null) {
      final loadId = loader.generation;
      if (await loader.prepare(controller, url)) {
        try {
          await _finishLoading(
            tuanweiLoadId: loadId,
          ).timeout(const Duration(seconds: 2));
        } catch (error) {
          AppLog.w('WebViewNoticePage', 'Notice navigation state failed: $error');
        }
      }
      return;
    }
    if (_beautifyScript.isNotEmpty) {
      try {
        await controller.evaluateJavascript(source: _beautifyScript);
      } catch (e) {
        AppLog.e(
          'WebViewNoticePage',
          '${widget.debugLabel} beautify script error: $e',
        );
      }
      if (_domReadyScript.isNotEmpty) {
        try {
          await controller.evaluateJavascript(source: _domReadyScript);
        } catch (e) {
          AppLog.e(
            'WebViewNoticePage',
            '${widget.debugLabel} dom ready script error: $e',
          );
          await _finishLoading();
        }
        return;
      }
    }
    await _finishLoading();
  }

  Future<void> _onDomReady(List<dynamic> arguments) async {
    final loader = _layoutLoader;
    if (loader != null) {
      loader.onDomReady(arguments);
      return;
    }
    await _finishLoading();
  }

  Future<void> _openInBrowser() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final current = await ctrl.getUrl();
    final uri = current ?? Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _goBack() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (await ctrl.canGoBack()) {
      _startNoticeNavigation();
      await ctrl.goBack();
    }
  }

  Future<void> _goForward() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (await ctrl.canGoForward()) {
      _startNoticeNavigation();
      await ctrl.goForward();
    }
  }

  @override
  void dispose() {
    _layoutLoader?.removeListener(_onTuanweiLoadingChanged);
    _layoutLoader?.dispose();
    // The retained DownloadWebView is the controller's sole owner.
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DownloadWebView.isSupported) {
      return WebViewUnsupportedPage(title: widget.title);
    }
    return _buildWebViewPage(context);
  }

  Widget _buildWebViewPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ctrl = _controller;
        if (ctrl != null && await ctrl.canGoBack()) {
          _startNoticeNavigation();
          await ctrl.goBack();
        } else if (mounted) {
          if (logicRootContext.mounted) Navigator.of(logicRootContext).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 152,
          centerTitle: true,
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.close,
                  onPressed: () {
                    if (logicRootContext.mounted) {
                      Navigator.of(logicRootContext).pop();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: l10n.goBack,
                  onPressed: _canGoBack ? _goBack : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  tooltip: l10n.goForward,
                  onPressed: _canGoForward ? _goForward : null,
                ),
              ],
            ),
          ),
          actions: [
            if (widget.downloadOptions != null)
              IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: l10n.downloadedAttachments,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NoticeDownloadedPage(
                      initialTab: widget.downloadOptions!.initialTab,
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: l10n.openInBrowser,
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              DownloadWebView(
                onWebViewCreated: _onWebViewCreated,
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialUserScripts: _isCampusNotice
                    ? UnmodifiableListView<UserScript>([
                        UserScript(
                          source: noticeLayoutDocumentStart,
                          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                          forMainFrameOnly: true,
                        ),
                      ])
                    : null,
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useWideViewPort: false,
                  // ArkWeb follows system appearance without reloading.
                  forceDark: _isCampusNotice ? ForceDark.AUTO : ForceDark.OFF,
                  forceDarkAccess: false,
                  supportZoom: _tuanweiLoader == null,
                  builtInZoomControls: _tuanweiLoader == null,
                  loadWithOverviewMode: _tuanweiLoader == null,
                ),
                onDownload: widget.downloadOptions == null
                    ? null
                    : (controller, request) =>
                          handleDownloadStartRequest(request),
                onLoadStart: _onLoadStart,
                onLoadStop: _onLoadStop,
                useNativeNoticeTheme: _isCampusNotice,
                onJsBeforeUnload:
                    _tuanweiLoader == null ? null : _onTuanweiBeforeUnload,
                onReceivedError: (controller, request, error) async {
                  AppLog.e(
                    'WebViewNoticePage',
                    '${widget.debugLabel} WebView error: $error',
                  );
                  final loader = _layoutLoader;
                  if (loader != null) {
                    if (request.isForMainFrame ?? false) {
                      await loader.onMainFrameError(controller, request.url);
                    }
                    return;
                  }
                  if ((request.isForMainFrame ?? false) &&
                      _errorHtmlTemplate.isNotEmpty) {
                    final html = _errorHtmlTemplate.replaceAll(
                      '{{error}}',
                      '${error.description} (${error.type})',
                    );
                    controller.loadData(data: html);
                  }
                },
              ),
              if (_layoutLoader != null &&
                  (_layoutLoader!.isLoading || _layoutLoader!.hasFailed))
                Positioned.fill(
                  child: TuanweiNoticeCover(
                    failed: _layoutLoader!.hasFailed,
                    onRetry: () => _layoutLoader!.retry(_controller),
                    onOpenBrowser: _openInBrowser,
                  ),
                ),
              if (_layoutLoader == null)
                IgnorePointer(
                  ignoring: !_loading,
                  child: AnimatedOpacity(
                    opacity: _loading ? 0.99 : 0,
                    duration: _loading
                        ? Duration.zero
                        : appConfigService.cardSizeAnimationDuration.value,
                    curve: appCurve,
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
              if (_pageAttachments.isNotEmpty &&
                  widget.downloadOptions != null &&
                  !(_layoutLoader?.isLoading ?? false) &&
                  !(_layoutLoader?.hasFailed ?? false))
                NoticeAttachmentFab(
                  items: _pageAttachments,
                  dirName: widget.downloadOptions!.attachmentDir,
                  downloadHeaders: widget.downloadOptions!.downloadHeaders,
                  onWebViewDownload: widget.downloadOptions!.useWebViewDownload
                      ? onWebViewDownload
                      : null,
                  boundarySize: Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ),
                  heroTag: widget.heroTag,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
