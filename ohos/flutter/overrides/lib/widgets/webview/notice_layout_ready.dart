import 'dart:convert';

/// Hide the original document before its first paint, while keeping layout live.
const noticeLayoutDocumentStart = r'''
(function () {
  if (window.top !== window ||
      !['jwc.scu.edu.cn', 'xgb.scu.edu.cn', 'tuanwei.scu.edu.cn'].includes(location.hostname)) return;
  // OH may replay document-start scripts on progress events.
  if (window.__bugaoshanNoticeGateInstalled) return;
  window.__bugaoshanNoticeGateInstalled = true;
  function install() {
    if (!document.documentElement) return false;
    if (document.getElementById('bugaoshan-notice-layout-gate')) return true;
    var style = document.createElement('style');
    style.id = 'bugaoshan-notice-layout-gate';
    style.textContent = 'html { opacity: 0 !important; }';
    document.documentElement.appendChild(style);
    return true;
  }
  if (!install()) {
    var observer = new MutationObserver(function () {
      if (install()) observer.disconnect();
    });
    observer.observe(document, { childList: true });
  }
})();
''';

/// Wait for parsed content before invoking the upstream beautifier once.
String noticeLayoutScript({
  required String beautifyScript,
  required String asset,
  required Uri url,
  required int loadId,
}) {
  final jwc = asset == 'assets/js/jwc_notice_beautify.js';
  final host = jwc ? 'jwc.scu.edu.cn' : 'xgb.scu.edu.cn';
  final selector = jwc
      ? '.tz-list, .list, #vsb_content, .detail-text, .v_news_content'
      : '.main-box > ul, .detail-content, .v_news_content';
  return '''
(function () {
  var expected = new URL(${jsonEncode(url.toString())});
  if (window.top !== window || location.hostname !== ${jsonEncode(host)} ||
      location.origin !== expected.origin || location.pathname !== expected.pathname ||
      location.search !== expected.search || document.readyState === 'loading' ||
      !document.head || !document.body || !document.querySelector(${jsonEncode(selector)})) return false;
  window.__bugaoshanNoticeReady = null;
  if (!window.__bugaoshanNoticeStyled) {
    $beautifyScript
    window.__bugaoshanNoticeStyled = true;
  }
  ${noticeLayoutCompletion(loadId: loadId, marker: '__bugaoshanNoticeReady')}
  return true;
})();
''';
}

String noticeLayoutReadyProbe({required Uri url, required int loadId}) => '''
(function () {
  var expected = new URL(${jsonEncode(url.toString())});
  return location.origin === expected.origin && location.pathname === expected.pathname &&
      location.search === expected.search && window.__bugaoshanNoticeReady === $loadId &&
      window.__bugaoshanNoticeStyled === true &&
      document.getElementById('bugaoshan-notice-layout-gate') === null;
})();
''';

/// Confirm stable geometry after resources/fonts settle, then reveal and paint.
/// The Dart loader owns the timeout/error UI; no timeout reveals raw content.
String noticeLayoutCompletion({required int loadId, required String marker}) => '''
  (function () {
    if (window.__bugaoshanLayoutCancel) window.__bugaoshanLayoutCancel();
    var href = location.href;
    var frame = 0;
    var stopped = false;
    var lastChange = performance.now();
    var previous = '';
    var stableFrames = 0;
    var mutation = new MutationObserver(changed);
    var resize = typeof ResizeObserver === 'function' ? new ResizeObserver(changed) : null;
    function changed() {
      lastChange = performance.now();
      stableFrames = 0;
    }
    function stop() {
      stopped = true;
      cancelAnimationFrame(frame);
      clearTimeout(deadline);
      mutation.disconnect();
      if (resize) resize.disconnect();
      if (window.__bugaoshanLayoutCancel === stop) window.__bugaoshanLayoutCancel = null;
    }
    window.__bugaoshanLayoutCancel = stop;
    var deadline = setTimeout(stop, 11000);
    mutation.observe(document.body, { subtree: true, childList: true, attributes: true, characterData: true });
    if (resize) {
      resize.observe(document.documentElement);
      resize.observe(document.body);
    }
    function tick() {
      if (stopped || location.href !== href) { stop(); return; }
      var box = document.body.getBoundingClientRect();
      var geometry = [innerWidth, innerHeight, box.width, box.height,
          document.documentElement.scrollHeight, scrollX, scrollY].join(',');
      var resourcesReady = document.readyState === 'complete' &&
          (!document.fonts || document.fonts.status === 'loaded');
      if (!resourcesReady || geometry !== previous) {
        previous = geometry;
        changed();
      } else {
        stableFrames++;
      }
      if (resourcesReady && stableFrames >= 3 && performance.now() - lastChange >= 250) {
        mutation.disconnect();
        if (resize) resize.disconnect();
        var gate = document.getElementById('bugaoshan-notice-layout-gate');
        if (gate) gate.remove();
        // Keep the Flutter cover while the now-visible document gets two frames.
        frame = requestAnimationFrame(function () {
          frame = requestAnimationFrame(function () {
            if (stopped || location.href !== href) { stop(); return; }
            stop();
            window[${jsonEncode(marker)}] = $loadId;
            if (window.flutter_inappwebview) {
              window.flutter_inappwebview.callHandler('DOMReady', $loadId);
            }
          });
        });
        return;
      }
      frame = requestAnimationFrame(tick);
    }
    frame = requestAnimationFrame(tick);
  })();
''';
