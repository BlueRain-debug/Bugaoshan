import 'dart:async';
import 'package:bugaoshan/utils/app_log.dart';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class WindowStateService with WindowListener {
  static const String _tag = 'WindowStateService';

  static const String _keyX = 'window_x';
  static const String _keyY = 'window_y';
  static const String _keyW = 'window_w';
  static const String _keyH = 'window_h';

  final SharedPreferences _prefs;
  Timer? _debounce;
  bool _closing = false;

  WindowStateService(this._prefs);

  static Future<WindowStateService> create(SharedPreferences prefs) async {
    final service = WindowStateService(prefs);

    await windowManager.ensureInitialized();

    final x = prefs.getDouble(_keyX);
    final y = prefs.getDouble(_keyY);
    final w = prefs.getDouble(_keyW);
    final h = prefs.getDouble(_keyH);
    final size = w != null && h != null ? Size(w, h) : null;
    // 位置以物理像素保存，尺寸仍是逻辑值。
    final position = x != null && y != null ? Offset(x, y) : null;

    // Validate saved position against current screen layout.
    // If the display configuration changed (resolution lowered, monitor
    // unplugged), the window could appear off-screen.
    Offset? clampedPosition;
    if (position != null && size != null) {
      clampedPosition = await _clampToScreen(position, size);
    }

    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: size,
        center: clampedPosition == null,
        minimumSize: const Size(300, 300),
      ),
    );

    if (clampedPosition != null) {
      // setPosition 会再乘一次窗口当前屏的 DPR，这里先除回去，
      // 保证最终落点是保存时的物理像素坐标。
      final currentDpr = _normalizeDpr(windowManager.getDevicePixelRatio());
      await windowManager.setPosition(clampedPosition / currentDpr);
    }

    // 接管关闭流程：onWindowClose 只是通知，窗口随后立即销毁，
    // 异步保存来不及落盘，因此拦截关闭并在保存完成后再销毁。
    await windowManager.setPreventClose(true);
    windowManager.addListener(service);
    await windowManager.show();
    return service;
  }

  static double _normalizeDpr(num? dpr) {
    return dpr != null && dpr > 0 ? dpr.toDouble() : 1.0;
  }

  /// 位置 [pos] 为物理像素，尺寸 [size] 为逻辑值。
  /// 同一窗口落在不同缩放比例的屏幕上时物理尺寸不同，因此每个屏幕都按
  /// 自己的 scaleFactor 单独换算后再比较。
  ///
  /// 返回原位置（窗口已可见）或钳制后的物理位置；
  /// 屏幕信息不可用时返回 `null`，由调用方居中。
  static Future<Offset?> _clampToScreen(Offset pos, Size size) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      if (displays.isEmpty) return pos;

      // 窗口落在该屏幕时对应的物理尺寸。
      Size physicalSizeOn(Display display) {
        final scale = _normalizeDpr(display.scaleFactor);
        return Size(size.width * scale, size.height * scale);
      }

      Rect windowRectOn(Display display) {
        final windowSize = physicalSizeOn(display);
        return Rect.fromLTWH(
          pos.dx,
          pos.dy,
          windowSize.width,
          windowSize.height,
        );
      }

      // Already mostly visible on any display — keep as-is.
      for (final display in displays) {
        final intersection = _displayRect(
          display,
        ).intersect(windowRectOn(display));
        if (intersection.width > 100 && intersection.height > 50) {
          return pos;
        }
      }

      // Off-screen or barely visible: pick the best target display.
      // Prefer the display with the largest overlap (handles the case where
      // the window slid slightly off the edge of its original display).
      // Fall back to the display whose center is closest.
      Display? best;
      double bestArea = 0;
      Display? fallback;
      double fallbackDist = double.infinity;
      for (final display in displays) {
        final screenRect = _displayRect(display);
        final windowRect = windowRectOn(display);
        final intersection = screenRect.intersect(windowRect);
        final area = intersection.isEmpty
            ? 0.0
            : intersection.width * intersection.height;
        if (area > bestArea) {
          bestArea = area;
          best = display;
        }
        final dist = (screenRect.center - windowRect.center).distance;
        if (dist < fallbackDist) {
          fallbackDist = dist;
          fallback = display;
        }
      }
      final target = best ?? fallback;
      if (target == null) return pos;

      final screen = _displayRect(target);
      final windowSize = physicalSizeOn(target);
      // If the window is larger than the screen, pin to screen origin.
      final maxX = screen.right - windowSize.width;
      final maxY = screen.bottom - windowSize.height;
      final clampedX = maxX >= screen.left
          ? pos.dx.clamp(screen.left, maxX)
          : screen.left;
      final clampedY = maxY >= screen.top
          ? pos.dy.clamp(screen.top, maxY)
          : screen.top;
      return Offset(clampedX, clampedY);
    } catch (logError, logStackTrace) {
      AppLog.e(
        _tag,
        '_clampToScreen 失败',
        error: logError,
        stackTrace: logStackTrace,
      );
      // If screen_retriever fails, accept the saved position.
      return pos;
    }
  }

  static Rect _displayRect(Display display) {
    // screen_retriever 给出的坐标已按各自屏幕的 scaleFactor 换算成逻辑值，
    // 乘回去得到物理像素，才能与 window_manager 换算后的窗口坐标比较。
    final scale = _normalizeDpr(display.scaleFactor);
    return Rect.fromLTWH(
      (display.visiblePosition?.dx ?? 0) * scale,
      (display.visiblePosition?.dy ?? 0) * scale,
      (display.visibleSize?.width ?? display.size.width) * scale,
      (display.visibleSize?.height ?? display.size.height) * scale,
    );
  }

  void _save() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _saveNow);
  }

  Future<void> _saveNow() async {
    try {
      // getPosition/getSize 返回的是按窗口当前所在屏 DPR 换算后的逻辑值，
      // 位置乘回 DPR 保存为物理像素，避免窗口在不同缩放比例的屏幕间
      // 移动后重启时偏移。
      final dpr = _normalizeDpr(windowManager.getDevicePixelRatio());
      final pos = await windowManager.getPosition();
      final size = await windowManager.getSize();
      await _prefs.setDouble(_keyX, pos.dx * dpr);
      await _prefs.setDouble(_keyY, pos.dy * dpr);
      await _prefs.setDouble(_keyW, size.width);
      await _prefs.setDouble(_keyH, size.height);
    } catch (logError, logStackTrace) {
      AppLog.e(_tag, '_saveNow 失败', error: logError, stackTrace: logStackTrace);
      // Best-effort save.
    }
  }

  @override
  void onWindowClose() {
    if (_closing) return;
    _closing = true;
    _debounce?.cancel();
    unawaited(_saveBeforeDestroy());
  }

  Future<void> _saveBeforeDestroy() async {
    try {
      await _saveNow();
    } finally {
      // destroy 只结束消息循环，引擎销毁期间窗口仍会留在屏幕上，
      // 先隐藏再销毁避免用户看到“点了关闭没反应”。
      await windowManager.hide();
      await windowManager.destroy();
    }
  }

  /// 取消待执行的保存并移除窗口监听。
  /// 服务目前随应用生命周期常驻，保留该方法以便替换实例或测试时清理。
  void dispose() {
    _debounce?.cancel();
    _debounce = null;
    windowManager.removeListener(this);
  }

  @override
  void onWindowMoved() => _save();

  @override
  void onWindowResized() => _save();
}
