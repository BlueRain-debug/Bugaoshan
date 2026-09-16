import 'dart:convert';

import 'notice_layout_ready.dart';

/// Adds OH layout rules around the current upstream script, in one document.
/// Unknown pages are not restyled; the loader keeps them covered.
String tuanweiMobileScript({
  required String beautifyScript,
  required Uri url,
  required int loadId,
}) => '''
(function () {
  if (window.top !== window || location.hostname !== 'tuanwei.scu.edu.cn') {
    return false;
  }
  var expected = new URL(${jsonEncode(url.toString())});
  if (location.origin !== expected.origin ||
      location.pathname !== expected.pathname || location.search !== expected.search) {
    return false;
  }
  if (document.readyState === 'loading') return false;
  var root = document.querySelector('.innerbox');
  if (!root || !document.head || !document.body ||
      !root.querySelector(':scope > ul > li a[href], article[id^="vsb_content"], .v_news_content')) {
    return false;
  }
  window.__bugaoshanTuanweiReady = null;
  $_tuanweiViewport
  if (!window.__bugaoshanNoticeStyled) {
    $beautifyScript
    window.__bugaoshanNoticeStyled = true;
  }
  $_tuanweiLayout
  ${noticeLayoutCompletion(loadId: loadId, marker: '__bugaoshanTuanweiReady')}
  return true;
})();
''';

/// A missed bridge callback may only reveal a document with this load's proof.
String tuanweiMobileReadyProbe({required Uri url, required int loadId}) => '''
(function () {
  var expected = new URL(${jsonEncode(url.toString())});
  return location.origin === expected.origin &&
      location.pathname === expected.pathname && location.search === expected.search &&
      window.__bugaoshanTuanweiReady === $loadId &&
      document.getElementById('bugaoshan-notice-layout-gate') === null &&
      document.getElementById('bugaoshan-tuanwei-mobile-layout') !== null &&
      document.querySelector('.innerbox[data-ohos-tuanwei-mobile]') !== null;
})();
''';

const _tuanweiViewport = r'''
  var viewports = Array.from(document.head.querySelectorAll('meta')).filter(function (meta) {
    return (meta.getAttribute('name') || '').toLowerCase() === 'viewport';
  });
  if (viewports.length === 0) {
    var viewport = document.createElement('meta');
    viewport.id = 'bugaoshan-tuanwei-viewport';
    viewport.name = 'viewport';
    document.head.appendChild(viewport);
    viewports.push(viewport);
  }
  viewports.forEach(function (meta) {
    meta.content = 'width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no';
  });
''';

const _tuanweiLayout = r'''
  function setLayout(element, properties) {
    Object.keys(properties).forEach(function (key) {
      element.style.setProperty(key, properties[key], 'important');
    });
  }
  // The upstream script sets inline !important widths: override only the known
  // layout containers, not every positioned element in the article.
  setLayout(document.documentElement, {
    'min-width': '0', width: '100%', 'max-width': 'none',
    margin: '0', padding: '0', 'box-sizing': 'border-box',
    'overflow-x': 'visible', 'touch-action': 'pan-x pan-y'
  });
  setLayout(document.body, {
    'min-width': '0', width: '100%', 'max-width': '640px',
    height: 'auto', margin: '0 auto', padding: '0',
    float: 'none', position: 'static', inset: 'auto', transform: 'none',
    'box-sizing': 'border-box', 'overflow-x': 'visible'
  });
  document.querySelectorAll('#bg, #bg2, .web, .innerbox').forEach(function (element) {
    if (element !== root && !element.contains(root)) return;
    setLayout(element, {
      'min-width': '0', width: '100%', 'max-width': '100%', height: 'auto',
      margin: '0', padding: '0', float: 'none', position: 'static',
      inset: 'auto', transform: 'none', 'box-sizing': 'border-box'
    });
  });
  root.setAttribute('data-ohos-tuanwei-mobile', '');
  root.querySelectorAll(':scope > ul, form, form h3, article[id^="vsb_content"], .v_news_content').forEach(function (element) {
    setLayout(element, {
      width: 'auto', 'min-width': '0', 'max-width': 'none', height: 'auto',
      float: 'none', position: 'static', inset: 'auto', transform: 'none',
      'box-sizing': 'border-box'
    });
  });
  root.querySelectorAll(':scope > ul > li, :scope > ul > li > a').forEach(function (element) {
    setLayout(element, {
      width: 'auto', 'min-width': '0', 'max-width': 'none', height: 'auto',
      'max-height': 'none', margin: '0', float: 'none', position: 'static',
      inset: 'auto', 'white-space': 'normal', 'text-indent': '0',
      'box-sizing': 'border-box'
    });
  });
  root.querySelectorAll('article[id^="vsb_content"] img, .v_news_content img').forEach(function (image) {
    setLayout(image, {
      width: 'auto', 'max-width': '100%', height: 'auto', 'min-width': '0'
    });
  });
  root.querySelectorAll('article[id^="vsb_content"] table, .v_news_content table').forEach(function (table) {
    // Wrap the original table so image/link event listeners remain attached.
    if (!table.parentElement || table.parentElement.closest('table')) return;
    if (!table.parentElement.hasAttribute('data-ohos-tuanwei-table')) {
      var scroll = document.createElement('div');
      scroll.setAttribute('data-ohos-tuanwei-table', '');
      table.parentNode.insertBefore(scroll, table);
      scroll.appendChild(table);
    }
    setLayout(table, {
      width: 'auto', 'min-width': '100%', 'max-width': 'none',
      'table-layout': 'auto', margin: '0', float: 'none'
    });
  });
  var style = document.getElementById('bugaoshan-tuanwei-mobile-layout');
  if (!style) {
    style = document.createElement('style');
    style.id = 'bugaoshan-tuanwei-mobile-layout';
    document.head.appendChild(style);
  }
  style.textContent = `
    [data-ohos-tuanwei-mobile] > ul > li {
      display: flex !important; overflow: visible !important;
    }
    [data-ohos-tuanwei-mobile] > ul > li > a {
      display: flex !important; flex: 1 1 0% !important;
      align-items: flex-start !important; line-height: 1.6 !important;
    }
    [data-ohos-tuanwei-mobile] .date-box {
      flex: 0 0 auto !important; width: auto !important;
    }
    [data-ohos-tuanwei-mobile] .notice-title {
      flex: 1 1 0% !important; min-width: 0 !important;
      white-space: normal !important; overflow: visible !important;
      max-height: none !important; -webkit-line-clamp: unset !important;
      overflow-wrap: anywhere !important;
    }
    [data-ohos-tuanwei-mobile] .pb_sys_common,
    [data-ohos-tuanwei-mobile] .p_pages {
      width: auto !important; min-width: 0 !important; max-width: 100% !important;
      height: auto !important; float: none !important; position: static !important;
      box-sizing: border-box !important; display: flex !important;
      flex-wrap: wrap !important; white-space: normal !important;
    }
    [data-ohos-tuanwei-mobile] .p_t { white-space: normal !important; }
    [data-ohos-tuanwei-mobile] .v_news_content > p,
    [data-ohos-tuanwei-mobile] .v_news_content > div {
      width: auto !important; min-width: 0 !important; max-width: 100% !important;
      margin-left: 0 !important; margin-right: 0 !important;
      box-sizing: border-box !important;
    }
    [data-ohos-tuanwei-mobile] article[id^="vsb_content"],
    [data-ohos-tuanwei-mobile] .v_news_content,
    [data-ohos-tuanwei-mobile] .fjxz a {
      overflow-wrap: anywhere !important;
    }
    [data-ohos-tuanwei-mobile] [data-ohos-tuanwei-table] {
      display: block !important; width: 100% !important;
      min-width: 0 !important; max-width: 100% !important;
      overflow-x: auto !important; box-sizing: border-box !important;
      -webkit-overflow-scrolling: touch; touch-action: pan-x pan-y;
    }
  `;
''';
