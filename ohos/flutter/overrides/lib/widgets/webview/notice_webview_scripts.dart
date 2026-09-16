/// Appends only the search control's theme rules to the upstream JWC script.
String withNoticeSearchTheme(String source, String? asset) {
  if (asset != 'assets/js/jwc_notice_beautify.js') return source;
  return '$source\n$_jwcSearchThemeScript';
}

const _jwcSearchThemeScript = r'''
(function () {
  if (location.hostname !== 'jwc.scu.edu.cn') return;
  var list = document.querySelector('.tz-list') || document.querySelector('.list');
  var bar = list && list.previousElementSibling;
  var input = bar && bar.querySelector('input[type="text"]');
  if (!input || !bar.querySelector('button')) return;
  input.setAttribute('data-bugaoshan-notice-search', '');
  var style = document.getElementById('bugaoshan-notice-search-theme');
  if (!style) {
    style = document.createElement('style');
    style.id = 'bugaoshan-notice-search-theme';
    document.head.appendChild(style);
  }
  // Both modes override the upstream script's one-time inline color choice.
  style.textContent = `
    input[data-bugaoshan-notice-search] {
      background: #fff !important; color: #333 !important;
      border-color: #e0e0e0 !important; color-scheme: light;
    }
    @media (prefers-color-scheme: dark) {
      input[data-bugaoshan-notice-search] {
        background: #1e1e1e !important; color: #e0e0e0 !important;
        border-color: #444 !important; color-scheme: dark;
      }
    }
  `;
})();
''';

/// Checks media queries and frame callbacks once after a theme change.
String webViewThemeProbeScript(int revision) => '''
(function () {
  window.__bugaoshanThemeFrame = null;
  requestAnimationFrame(function () {
    window.__bugaoshanThemeFrame = $revision;
  });
  return JSON.stringify({
    ready: document.readyState,
    visibility: document.visibilityState,
    dark: matchMedia('(prefers-color-scheme: dark)').matches,
    width: innerWidth, height: innerHeight,
    scrollX: scrollX, scrollY: scrollY
  });
})();
''';

String webViewThemeFrameScript(int revision) => '''
JSON.stringify({
  frameCallback: window.__bugaoshanThemeFrame === $revision,
  visibility: document.visibilityState
});
''';
