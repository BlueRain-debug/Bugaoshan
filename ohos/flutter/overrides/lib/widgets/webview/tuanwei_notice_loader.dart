import 'dart:async';

import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'tuanwei_mobile_layout.dart';

/// A page is revealed only after the current document confirms its layout.
typedef NoticeLayoutScript = String Function({
  required String beautifyScript,
  required Uri url,
  required int loadId,
});

typedef NoticeLayoutProbe = String Function({
  required Uri url,
  required int loadId,
});

class TuanweiNoticeLoader extends NoticeLayoutLoader {
  TuanweiNoticeLoader({required Future<String> Function() loadScript})
    : super(
        loadScript: loadScript,
        buildScript: tuanweiMobileScript,
        readyProbe: tuanweiMobileReadyProbe,
      );
}

class NoticeLayoutLoader extends ChangeNotifier {
  NoticeLayoutLoader({
    required Future<String> Function() loadScript,
    required NoticeLayoutScript buildScript,
    required NoticeLayoutProbe readyProbe,
  }) : _loadScript = loadScript,
       _buildScript = buildScript,
       _readyProbe = readyProbe {
    start();
  }

  final Future<String> Function() _loadScript;
  final NoticeLayoutScript _buildScript;
  final NoticeLayoutProbe _readyProbe;
  Future<String>? _script;
  Timer? _watchdog;
  Completer<bool>? _ready;
  int _generation = 0;
  bool _disposed = false;
  bool _preparing = false;
  bool _isLoading = true;
  bool _hasFailed = false;

  int get generation => _generation;
  bool get isLoading => _isLoading;
  bool get hasFailed => _hasFailed;

  bool _isCurrent(int loadId) =>
      !_disposed && !_hasFailed && loadId == _generation;

  void _cancelPending() {
    _watchdog?.cancel();
    _watchdog = null;
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) ready.complete(false);
  }

  void start() {
    if (_disposed) return;
    _cancelPending();
    final loadId = ++_generation;
    _isLoading = true;
    _hasFailed = false;
    _preparing = false;
    _watchdog = Timer(
      const Duration(seconds: 30),
      () => _fail(loadId, 'Page loading timed out'),
    );
    notifyListeners();
  }

  void _fail(int loadId, String reason) {
    if (!_isCurrent(loadId)) return;
    _cancelPending();
    _isLoading = false;
    _hasFailed = true;
    AppLog.w('NoticeLayout', reason);
    notifyListeners();
  }

  void onDomReady(List<dynamic> arguments) {
    if (_disposed ||
        _hasFailed ||
        arguments.length != 1 ||
        arguments.first != _generation) {
      return;
    }
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.complete(true);
  }

  Future<bool> prepare(InAppWebViewController controller, Uri? url) async {
    if (_disposed || _hasFailed || !_isLoading || _preparing) return false;
    final loadId = _generation;
    _preparing = true;
    try {
      final currentUrl = await controller.getUrl().timeout(
        const Duration(seconds: 2),
      );
      if (!_isCurrent(loadId)) return false;
      if (url != null &&
          currentUrl != null &&
          url.removeFragment() != currentUrl.removeFragment()) {
        return false;
      }
      final documentUrl = currentUrl ?? url;
      if (documentUrl == null) throw StateError('Document URL unavailable');
      final script = await (_script ??= _loadScript()).timeout(
        const Duration(seconds: 5),
      );
      if (!_isCurrent(loadId)) return false;
      if (script.isEmpty) throw StateError('Notice script unavailable');
      final ready = Completer<bool>();
      _ready = ready;
      final source = _buildScript(
        beautifyScript: script,
        url: documentUrl,
        loadId: loadId,
      );
      final waiting = Stopwatch()..start();
      // OH can emit onLoadStop at first paint, before the notice DOM exists.
      // A false result has not run the upstream script, so retrying is safe.
      while (_isCurrent(loadId) &&
          waiting.elapsed < const Duration(seconds: 12)) {
        final applied = await controller
            .evaluateJavascript(source: source)
            .timeout(const Duration(seconds: 3));
        if (!_isCurrent(loadId)) return false;
        if (applied == true) {
          var confirmed = await ready.future.timeout(
            const Duration(seconds: 12),
            onTimeout: () => false,
          );
          if (!_isCurrent(loadId)) return false;
          if (!confirmed) {
            final proof = await controller
                .evaluateJavascript(
                  source: _readyProbe(
                    url: documentUrl,
                    loadId: loadId,
                  ),
                )
                .timeout(const Duration(seconds: 2));
            confirmed = proof == true;
          }
          if (!_isCurrent(loadId)) return false;
          if (!confirmed) {
            _fail(loadId, 'Document did not confirm settled layout');
            return false;
          }
          _watchdog?.cancel();
          _watchdog = null;
          _isLoading = false;
          notifyListeners();
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      _fail(loadId, 'Notice content was not ready for layout');
    } catch (error) {
      if (_isCurrent(loadId)) {
        _fail(loadId, 'Notice layout failed: $error');
      }
    } finally {
      if (loadId == _generation) {
        _preparing = false;
        _ready = null;
      }
    }
    return false;
  }

  Future<void> onMainFrameError(
    InAppWebViewController controller,
    Uri failedUrl,
  ) async {
    final loadId = _generation;
    try {
      final current = await controller.getUrl().timeout(
        const Duration(seconds: 2),
      );
      if (!_isCurrent(loadId)) return;
      if (current != null &&
          current.removeFragment() != failedUrl.removeFragment()) {
        return;
      }
      _fail(loadId, 'Notice page failed to load');
    } catch (error) {
      _fail(loadId, 'Cannot confirm failed document: $error');
    }
  }

  Future<void> retry(InAppWebViewController? controller) async {
    if (_disposed) return;
    _script = null;
    start();
    final loadId = _generation;
    if (controller == null) {
      _fail(loadId, 'WebView unavailable');
      return;
    }
    try {
      // Paint the opaque cover before reloading the currently displayed URL.
      await WidgetsBinding.instance.endOfFrame;
      if (!_isCurrent(loadId)) return;
      await controller.reload().timeout(const Duration(seconds: 5));
    } catch (error) {
      _fail(loadId, 'Reload failed: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelPending();
    super.dispose();
  }
}

/// Fully opaque from the first frame, including translucent app themes.
class TuanweiNoticeCover extends StatelessWidget {
  const TuanweiNoticeCover({
    super.key,
    required this.failed,
    required this.onRetry,
    required this.onOpenBrowser,
  });

  final bool failed;
  final VoidCallback onRetry;
  final VoidCallback onOpenBrowser;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlockSemantics(
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor.withAlpha(255),
        child: Center(
          child: failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.loadFailed),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                    TextButton.icon(
                      onPressed: onOpenBrowser,
                      icon: const Icon(Icons.open_in_browser),
                      label: Text(l10n.openInBrowser),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
