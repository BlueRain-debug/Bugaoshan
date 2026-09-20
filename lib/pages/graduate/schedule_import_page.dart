import 'dart:async';
import 'dart:collection';

import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/providers/course_provider.dart';
import 'package:bugaoshan/services/api/gs_api_service.dart';
import 'package:bugaoshan/services/graduate_schedule_capture.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/utils/constants.dart';
import 'package:bugaoshan/utils/graduate_schedule_parser.dart';
import 'package:bugaoshan/widgets/dialog/dialog.dart';
import 'package:bugaoshan/widgets/webview/webview_unsupported_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:os_type/os_type.dart';

/// 研究生课表导入。
///
/// **直连优先**（2026-09-15 接口定案后新增）：进入页面先尝试用 SCU 会话
/// 直连 `xspkjgcx.do` 拉取课表（[GsApiService.fetchSchedule]），成功则直接
/// 展示结果并导入，无需打开网页；学期第 1 周周一由首次上课日期（SCSKRQ）
/// 反推，不再依赖「本周一」近似。
///
/// 直连失败（ehall 会话未建立 / 未登录 / 接口异常）时**降级为 WebView
/// 抓取兜底**：加载 [kGsSchedulePageUrl]，并在文档开始前注入
/// [kGraduateScheduleCaptureScript]，由页面自己去取课表数据时顺手把响应体
/// 记下来；Dart 侧轮询取走，用 [graduateCoursesFromCapturedJson] 识别出课程，
/// 再写进课表。兜底方案需用户在页面内登录一次 ehall。
class GraduateScheduleImportPage extends StatefulWidget {
  const GraduateScheduleImportPage({super.key});

  @override
  State<GraduateScheduleImportPage> createState() =>
      _GraduateScheduleImportPageState();
}

class _GraduateScheduleImportPageState
    extends State<GraduateScheduleImportPage> {
  static const String _tag = 'GraduateScheduleImportPage';

  /// 轮询间隔：够快能及时反馈，又不会把 WebView 打满。
  static const Duration _pollInterval = Duration(milliseconds: 1500);

  InAppWebViewController? _controller;
  Timer? _pollTimer;
  List<GraduateCaptureEntry> _entries = const [];
  List<Course> _courses = const [];
  List<String> _captureUrls = const [];
  bool _pageLoading = true;
  bool _importing = false;

  /// 直连三态：进行中 / 成功（隐藏 WebView）/ 失败（回退 WebView）。
  bool _directPhase = true;
  bool _directAvailable = false;
  DateTime? _directSemesterStart;

  @override
  void initState() {
    super.initState();
    _tryDirectFetch();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// 直连拉取课表；成功时隐藏 WebView，失败时静默回退。
  Future<void> _tryDirectFetch() async {
    try {
      final api = getIt<GsApiService>();
      final courses = await api.fetchSchedule();
      if (!mounted) return;
      if (courses.isEmpty) {
        setState(() {
          _directPhase = false;
          _directAvailable = false;
        });
        return;
      }

      DateTime? semesterStart;
      try {
        final term = await api.latestSemesterCode();
        if (term != null) {
          semesterStart = semesterStartMondayFromFirstClassRows(
            await api.fetchFirstClassRows(term),
          );
        }
      } catch (e) {
        // 学期起始日推算失败不影响导入，仅退回「本周一」近似。
        AppLog.w(_tag, '直连学期起始日推算失败：$e');
      }

      if (!mounted) return;
      setState(() {
        _directPhase = false;
        _directAvailable = true;
        _courses = courses;
        _directSemesterStart = semesterStart;
      });
      AppLog.i(_tag, '直连获取课表成功：${courses.length} 门课');
    } catch (e) {
      AppLog.i(_tag, '直连获取课表失败（回退 WebView 兜底）：$e');
      if (!mounted) return;
      setState(() {
        _directPhase = false;
        _directAvailable = false;
      });
    }
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => unawaited(_pollCapture()),
    );
  }

  /// 读取页面里累积的捕获结果；有新数据才重新解析。
  Future<void> _pollCapture() async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final Object? raw;
    try {
      raw = await controller.evaluateJavascript(
        source: kGraduateScheduleCaptureQuery,
      );
    } catch (e) {
      AppLog.w(_tag, '读取捕获结果失败：$e');
      return;
    }
    if (!mounted) return;

    final entries = graduateCaptureEntriesFrom(raw is String ? raw : null);
    if (entries.length == _entries.length) return;

    final courses = graduateCoursesFromCapturedJson(
      entries.map((e) => e.body).toList(),
    );
    setState(() {
      _entries = entries;
      _courses = courses;
      _captureUrls = {
        for (final entry in entries)
          if (entry.url.isNotEmpty) redactCaptureUrl(entry.url),
      }.toList();
    });
    AppLog.i(_tag, '捕获 ${entries.length} 段响应，识别出 ${courses.length} 门课程');
  }

  Future<void> _reload() async {
    // 直连模式：刷新 = 重试直连。
    if (_directAvailable || _directPhase) {
      await _tryDirectFetch();
      return;
    }
    setState(() {
      _entries = const [];
      _courses = const [];
      _captureUrls = const [];
      _pageLoading = true;
    });
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(
        source: 'window.$kGraduateCaptureGlobal = [];',
      );
      await controller.reload();
    } catch (e) {
      AppLog.w(_tag, '重新加载失败：$e');
    }
  }

  /// 课表覆盖的最大周数：不少于默认 20 周，课程周次更靠后就跟着放大。
  int _totalWeeksFor(List<Course> courses) {
    var maxEnd = kDefaultTotalWeeks;
    for (final course in courses) {
      if (course.endWeek > maxEnd) maxEnd = course.endWeek;
    }
    return maxEnd;
  }

  Future<void> _import() async {
    if (_courses.isEmpty || _importing) return;

    final l10n = AppLocalizations.of(context)!;
    final provider = getIt<CourseProvider>();
    final scheduleName = l10n.graduateScheduleImportName;
    setState(() => _importing = true);

    // 先定下「目标课表的形状」，同时用它做范围校验与写库。
    // 直连成功时用首次上课日期反推的第 1 周周一；兜底路径退回「本周一」近似。
    final config = ScheduleConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      semesterName: scheduleName,
      semesterStartDate: _directSemesterStart ?? DateTime.now().toMonday(),
      totalWeeks: _totalWeeksFor(_courses),
    );
    // 按课程的主导校区挑时间表（江安 / 望江华西），节数非默认时不改动。
    ScheduleConfig.applyCampusTimeSlotsForCourses(config, _courses);

    // 借用本科导入的校验标准，但逐条过滤而非中断整次导入。
    final clamped = clampGraduateCourses(
      _courses,
      totalWeeks: config.totalWeeks,
      sectionsPerDay: config.timeSlots.length,
    );
    if (clamped.dropped > 0) {
      AppLog.w(_tag, '丢弃 ${clamped.dropped} 门越界课程（共 ${_courses.length} 门）');
    }
    final courses = clamped.courses;
    if (courses.isEmpty) {
      AppLog.e(_tag, '解析出的 ${_courses.length} 门课程全部越界，放弃导入');
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.graduateScheduleImportFailed)),
      );
      return;
    }

    // 目标课表已存在时是「整表替换」：同名课表里的课程会被全部清空，
    // 且导入完成后会切换过去——先确认一次，避免从课表页入口误触发覆盖。
    final existingId = provider.findScheduleIdByName(scheduleName);
    if (existingId != null) {
      final overwrite = await showYesNoDialog(
        title: l10n.graduateScheduleImportOverwriteTitle,
        content: l10n.graduateScheduleImportOverwriteBody(scheduleName),
      );
      if (!mounted) return;
      if (overwrite != true) {
        setState(() => _importing = false);
        return;
      }
    }

    try {
      if (existingId != null) {
        await provider.replaceScheduleCourses(existingId, courses);
        await provider.switchSchedule(existingId);
      } else {
        await provider.addSchedule(config);
        await provider.replaceScheduleCourses(config.id, courses);
        await provider.switchSchedule(config.id);
      }
      AppLog.i(_tag, '导入完成：${courses.length} 门课程 → $scheduleName');
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.graduateScheduleImportDoneTo(scheduleName)),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      AppLog.e(_tag, '导入失败：$e');
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.graduateScheduleImportFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // 直连进行中：整页 loading，不渲染 WebView。
    if (_directPhase) {
      return Scaffold(
        appBar: _buildAppBar(l10n),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 直连成功：只显示结果与导入按钮，无需打开网页。全平台一致。
    if (_directAvailable) {
      return Scaffold(appBar: _buildAppBar(l10n), body: _buildStatusBar(l10n));
    }

    // 直连失败：Web 被跨域限制（ehall 不放行跨域凭据请求，实测 2026-09-15），
    // 且无 WebView 兜底——如实提示需要原生客户端。鸿蒙无 WebView，提示重试。
    if (kIsWeb) {
      // preview 分支的 WebViewUnsupportedPage 只接收 title（无 message 参数）
      return WebViewUnsupportedPage(title: l10n.graduateScheduleImport);
    }
    if (OS.isHarmony) {
      return _buildNoWebViewGuide(l10n);
    }

    return Scaffold(appBar: _buildAppBar(l10n), body: _fallbackBody(l10n));
  }

  /// 鸿蒙的无兜底引导页：无 WebView 实现，仅提示可重试直连或换用其他客户端。
  Widget _buildNoWebViewGuide(AppLocalizations l10n) {
    return Scaffold(
      appBar: _buildAppBar(l10n),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.public,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.graduateScheduleImportNoWebView,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _tryDirectFetch,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.graduateScheduleImportRetryDirect),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n) {
    return AppBar(
      centerTitle: true,
      title: Text(l10n.graduateScheduleImport),
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.close,
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: l10n.retry,
          onPressed: _reload,
        ),
      ],
    );
  }

  /// 兜底路径的页面主体：WebView + 状态栏。
  Widget _fallbackBody(AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(child: _buildWebView()),
        _buildStatusBar(l10n),
      ],
    );
  }

  Widget _buildWebView() {
    return Stack(
      children: [
        InAppWebView(
          onWebViewCreated: _onWebViewCreated,
          initialUrlRequest: URLRequest(url: WebUri(kGsSchedulePageUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useWideViewPort: true,
            domStorageEnabled: true,
          ),
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: kGraduateScheduleCaptureScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          onLoadStart: (_, _) {
            if (mounted) setState(() => _pageLoading = true);
          },
          onLoadStop: (_, _) {
            if (mounted) setState(() => _pageLoading = false);
          },
          onReceivedError: (_, request, error) {
            AppLog.e(_tag, 'WebView 加载失败：${error.description}');
            if (mounted) setState(() => _pageLoading = false);
          },
        ),
        if (_pageLoading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildStatusBar(AppLocalizations l10n) {
    final hasCourses = _courses.isNotEmpty;
    final hasEntries = _entries.isNotEmpty;

    final String status;
    if (hasCourses) {
      status = l10n.graduateScheduleImportFound;
    } else if (hasEntries) {
      status = l10n.graduateScheduleImportEmpty;
    } else {
      status = l10n.graduateScheduleImportWaiting;
    }

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasCourses
                        ? Icons.check_circle_outline
                        : Icons.hourglass_empty,
                    size: 20,
                    color: hasCourses
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (hasCourses)
                    Text(
                      '${_courses.length}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              // 抓到的接口地址（已脱敏）——用于日后改为直接请求。
              if (hasEntries) ...[
                const SizedBox(height: 4),
                Text(
                  _captureUrls.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: hasCourses && !_importing ? _import : null,
                  icon: const Icon(Icons.download_done),
                  label: Text(l10n.graduateScheduleImportAction),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
