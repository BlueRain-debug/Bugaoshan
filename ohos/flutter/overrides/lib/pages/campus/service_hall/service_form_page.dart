import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/providers/scu_auth_provider.dart';
import 'package:bugaoshan/services/api/service_api_service.dart';
import 'package:bugaoshan/services/api/service_form_models.dart';
import 'package:bugaoshan/services/api/service_plugin_models.dart';
import 'package:bugaoshan/services/auth/scu_exceptions.dart';
import 'package:bugaoshan/services/auth/service_auth.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/utils/auth_logger.dart';
import 'package:bugaoshan/widgets/common/login_required_widget.dart';
import 'package:bugaoshan/widgets/common/service_region_picker.dart';
import 'package:bugaoshan/widgets/common/styled_card.dart';
import 'package:bugaoshan/pages/campus/service_hall/service_app_catalog.dart';
import 'package:bugaoshan/pages/campus/service_hall/service_field_widgets.dart';
import 'package:bugaoshan/pages/campus/service_hall/service_form_controller.dart';

/// 办事大厅通用动态表单页。
///
/// 字段结构由服务端驱动（与前端发起页加载顺序一致，被动抓包确认；
/// 其中 1、2 互不依赖，本实现并行发起）：
/// 1. `start-data` 提供字段权限（require/writable/readable/front_readonly/
///    hidden/forbidden）与预填值；
/// 2. `start-info` 提供 bpmn_id 与 form 列表（form_id/version_id，不含插件）；
/// 3. `get-formv?bpmn_id&id=<currform>` 提供字段插件定义（标签/类型/选项/
///    排序/DataSource 配置/ShowHide 显隐规则/Validate 校验规则）；
/// 4. 任一环节失败 → [ServiceAppInfo.fallbackSchema]（仅 350）→
///    失败封闭（错误 + 重试，绝不渲染猜测的表单）。
///
/// 提交流程：校验（[ServiceFormController.validate]）→ 逐 File 字段上传
/// 附件 → 组装 `form_data`（[ServiceFormController.buildFormData]，记入
/// AuthLogger 便于诊断）→ `POST /site/apps/launch`。
class ServiceFormPage extends StatefulWidget {
  final ServiceAppInfo app;

  const ServiceFormPage({super.key, required this.app});

  @override
  State<ServiceFormPage> createState() => _ServiceFormPageState();
}

class _ServiceFormPageState extends State<ServiceFormPage> {
  ServiceFormSchema? _schema;
  ServiceFormController? _controller;
  bool _schemaLoading = false;

  /// 省市区数据（在线加载，失败回退本地 asset）。
  List<ServiceRegionNode> _regions = const [];
  bool _regionsLoading = false;

  bool _submitting = false;
  late int _sessionEpoch;

  bool _isCurrentSession(int epoch) =>
      mounted && epoch == _sessionEpoch &&
      epoch == getIt<ScuAuthProvider>().sessionEpoch;

  /// 发起人部门 id（select-department 接口；失败回退默认值）。
  String? _starterDepartId;

  /// 提交成功后自增，强制字段组件重建（清空内部 controller）。
  int _resetCounter = 0;

  @override
  void initState() {
    super.initState();
    _sessionEpoch = getIt<ScuAuthProvider>().sessionEpoch;
    getIt<ScuAuthProvider>().addListener(_onAuthChanged);
    getIt<ServiceAuth>().addListener(_onServiceAuthChanged);
    // 省市区数据有本地 asset 兜底，无需登录即可加载。
    unawaited(_loadRegions());
    if (getIt<ScuAuthProvider>().isLoggedIn) {
      unawaited(_loadSchema());
    }
  }

  @override
  void dispose() {
    getIt<ScuAuthProvider>().removeListener(_onAuthChanged);
    getIt<ServiceAuth>().removeListener(_onServiceAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final epoch = getIt<ScuAuthProvider>().sessionEpoch;
    if (epoch != _sessionEpoch) {
      _sessionEpoch = epoch;
      _schema = null;
      _controller = null;
      _starterDepartId = null;
      _schemaLoading = false;
      _submitting = false;
      _resetCounter++;
    }
    // 已加载过 schema 就不重复加载——重建 controller 会清空用户已填内容
    if (getIt<ScuAuthProvider>().isLoggedIn && _schema == null) {
      unawaited(_loadSchema());
    }
    if (mounted) setState(() {});
  }

  void _onServiceAuthChanged() {
    if (getIt<ServiceAuth>().isReady && _schema == null) {
      // SSO 就绪后加载表单（initState 时可能还没就绪，导致信息空白）
      unawaited(_loadSchema());
    }
    if (mounted) setState(() {});
  }

  /// 加载表单 schema（start-data + start-info → build → fallback 链）。
  Future<void> _loadSchema() async {
    if (!getIt<ScuAuthProvider>().isLoggedIn) return;
    if (_schemaLoading) return;
    final epoch = _sessionEpoch;
    setState(() => _schemaLoading = true);
    try {
      final schema = await _fetchSchema(epoch);
      if (!_isCurrentSession(epoch)) return;
      setState(() {
        _schema = schema;
        _controller = ServiceFormController(
          schema,
          overrides: widget.app.overrides,
        );
      });
      // schema 就绪后取各 DataSource 值（不阻塞渲染；
      // starterDepartId 已在 _fetchSchema 中先行请求）
      unawaited(_loadDataSources());
    } catch (e) {
      AppLog.e('ServiceFormPage', 'Schema load failed: $e');
    } finally {
      if (_isCurrentSession(epoch)) setState(() => _schemaLoading = false);
    }
  }

  /// schema 获取链（与前端一致）：start-data ∥ start-info（bpmn_id + form
  /// 列表）→ get-formv（currform 的插件）→ 每事项 fallbackSchema。
  ///
  /// start-data 与 start-info 都只依赖 appId、互不输出了对方需要的值，
  /// 并行发起省一次串行 RTT；仅 get-formv 必须等两者结果（currform + bpmn_id）。
  Future<ServiceFormSchema> _fetchSchema(int epoch) async {
    final api = getIt<ServiceApiService>();
    final appId = widget.app.appId;
    final startDataFuture = api.fetchFormSchema(appId);
    final startInfoFuture = api.fetchStartInfo(appId);

    // start-data 是 auth/data 的唯一来源，必须成功。
    final ServiceFormDefinition startData;
    try {
      startData = await startDataFuture;
    } catch (e) {
      // start-info 的结果已无人消费，吞掉避免悬空的 unhandled error
      startInfoFuture.ignore();
      rethrow;
    }

    // 先取发起人部门 id（get-formv 与 data-source 请求都带它）
    if (!_isCurrentSession(epoch)) throw const UnauthenticatedException();
    unawaited(_loadStarterDepartId(epoch));

    try {
      final startInfoD = await startInfoFuture;
      if (!_isCurrentSession(epoch)) throw const UnauthenticatedException();
      final bpmnId = startInfoD['bpmn_id']?.toString() ?? '';
      // currform 指定当前生效表单（如 337 为 1396 而非 1397）
      final formId = startData.currform.isNotEmpty
          ? startData.currform.first.toString()
          : '';
      if (bpmnId.isEmpty || formId.isEmpty) {
        throw StateError('start-info 缺少 bpmn_id 或 currform');
      }
      final formvD = await api.fetchFormPlugins(
        bpmnId: bpmnId,
        formId: formId,
        starterDepartId:
            _starterDepartId ?? ServiceApiService.kDefaultStarterDepartId,
      );
      return ServiceFormSchema.build(
        appId: appId,
        formvD: formvD,
        startData: startData,
      );
    } catch (e) {
      AppLog.w('ServiceFormPage', 'Live schema unavailable: $e');
    }
    final fallback = widget.app.fallbackSchema;
    if (fallback != null) {
      getIt<AuthLogger>().w(
        'SERVICE',
        'appId=$appId 实时表单定义不可用，使用硬编码 fallback schema',
      );
      return fallback(startData);
    }
    throw StateError('appId=$appId 无可用表单定义');
  }

  Future<void> _loadStarterDepartId(int epoch) async {
    try {
      final id = await getIt<ServiceApiService>().fetchStarterDepartId(
        widget.app.appId,
      );
      if (!_isCurrentSession(epoch) || id == null) return;
      setState(() => _starterDepartId = id);
    } catch (e) {
      AppLog.w('ServiceFormPage', 'Starter depart id load skipped: $e');
    }
  }

  /// 逐个 DataSource 字段取数（如辅导员），经
  /// [ServiceFormController.applyDataSourceValue] 分发：
  /// 单值 → 本字段 + resultKey 配对字段；setplugin → mapConfig 多列分发。
  /// 失败不阻塞（提交时整字段省略，350 已验证行为）。
  Future<void> _loadDataSources() async {
    final epoch = _sessionEpoch;
    final schema = _schema;
    final controller = _controller;
    if (schema == null || controller == null) return;
    for (final p in schema.dataSourcePlugins) {
      if (!_isCurrentSession(epoch)) return;
      try {
        final d = await getIt<ServiceApiService>().fetchDataSourceValue(
          appId: widget.app.appId,
          ref: p.dataSource!,
          starterDepartId:
              _starterDepartId ?? ServiceApiService.kDefaultStarterDepartId,
        );
        if (!_isCurrentSession(epoch) || !identical(controller, _controller)) return;
        if (d == null) continue;
        setState(() => controller.applyDataSourceValue(p, d['list']));
      } catch (e) {
        AppLog.w('ServiceFormPage', 'DataSource ${p.key} load skipped: $e');
      }
    }
  }

  /// 从本地 asset 加载省市区数据（在线接口优先，失败回退）。
  Future<void> _loadRegions() async {
    if (_regions.isNotEmpty || _regionsLoading) return;
    setState(() => _regionsLoading = true);
    try {
      List<dynamic> data;
      try {
        if (!getIt<ScuAuthProvider>().isLoggedIn) {
          throw StateError('not logged in');
        }
        data = await getIt<ServiceApiService>().fetchProvinces();
        if (data.isEmpty) throw StateError('empty provinces');
      } catch (e) {
        AppLog.w(
          'ServiceFormPage',
          'Region online load failed, fallback to asset: $e',
        );
        final raw = await rootBundle.loadString('assets/region_data.json');
        data = jsonDecode(raw) as List;
      }
      if (mounted) {
        setState(() {
          _regions = data
              .map((e) => ServiceRegionNode.fromJson(e as Map<String, dynamic>))
              .toList(growable: false);
        });
      }
    } catch (e) {
      AppLog.w('ServiceFormPage', 'Region load skipped: $e');
    } finally {
      if (mounted) setState(() => _regionsLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting || !getIt<ScuAuthProvider>().isLoggedIn) return;
    final epoch = _sessionEpoch;
    final l10n = AppLocalizations.of(context)!;
    final controller = _controller;
    if (controller == null) return;

    // 校验：动态必填 + 服务端 Validate 规则 + 每事项附加校验
    final issue = controller.validate();
    if (issue != null) {
      if (issue.kind == ServiceValidationKind.required) {
        final p = _schema?.pluginByKey(issue.fieldKey);
        _showSnack(
          l10n.serviceFormRequired(
            p == null ? issue.fieldKey : controller.labelOf(p),
          ),
          isError: true,
        );
      } else {
        // Validate 插件的服务端 alert 原文优先（如 356/357 的日期提示），
        // 缺省回退 350 的日期顺序文案
        _showSnack(issue.message ?? l10n.leaveEndAfterStart, isError: true);
      }
      return;
    }

    void checkSession() {
      if (!_isCurrentSession(epoch) || !identical(controller, _controller)) {
        throw const UnauthenticatedException('登录状态已改变');
      }
    }

    // Upload against a submission snapshot. Never replace the visible File
    // fields while uploading; every failure leaves the user's form intact.
    final draft = ServiceFormController(controller.schema, overrides: controller.overrides);
    draft.values
      ..clear()
      ..addAll(controller.values.map((key, value) => MapEntry(
        key,
        value is List ? List.of(value) : value is Set ? Set.of(value) : value,
      )));
    final starterDepartId =
        _starterDepartId ?? ServiceApiService.kDefaultStarterDepartId;
    setState(() => _submitting = true);
    try {
      final api = getIt<ServiceApiService>();
      final appId = widget.app.appId;
      for (final p in schemaEditableFilePlugins().toList()) {
        checkSession();
        final files = draft.values[p.key];
        final uploaded = <ServiceAttachment>[];
        if (files is List) {
          for (final file in files) {
            checkSession();
            if (file is File) {
              uploaded.add(await api.uploadAttachment(file, appId: appId));
              checkSession();
            } else if (file is ServiceAttachment) {
              uploaded.add(file);
            }
          }
        }
        draft.values[p.key] = uploaded;
      }

      checkSession();
      final formData = draft.buildFormData();
      AppLog.i('SERVICE', 'Submitting matter: $appId');
      await api.submitMatter(
        appId,
        formData,
        starterDepartId: starterDepartId,
      );
      checkSession();
      _showSnack(l10n.leaveSubmitSuccess);
      setState(() {
        controller.resetToPrefill();
        _resetCounter++;
      });
    } on UnauthenticatedException {
      if (_isCurrentSession(epoch)) _showSnack(l10n.loginRequired, isError: true);
    } catch (error) {
      AppLog.e('ServiceFormPage', 'Submit failed: $error');
      if (_isCurrentSession(epoch)) _showSnack(l10n.leaveSubmitFailed, isError: true);
    } finally {
      if (_isCurrentSession(epoch)) setState(() => _submitting = false);
    }
  }

  /// 当前可见的 File 类型可编辑字段。
  Iterable<ServiceFormPlugin> schemaEditableFilePlugins() {
    final schema = _schema;
    final controller = _controller;
    if (schema == null || controller == null) return const [];
    return schema.editablePlugins.where(
      (p) => p.type == ServiceFieldType.file && controller.isFieldVisible(p),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.app.title(l10n))),
      body: !getIt<ScuAuthProvider>().isLoggedIn
          ? const LoginRequiredWidget()
          : _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final schema = _schema;
    final controller = _controller;
    if (_schemaLoading && schema == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (schema == null || controller == null) {
      return _errorState(l10n);
    }
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard(l10n),
        const SizedBox(height: 12),
        for (final p in controller.displayPlugins) ...[
          if (p.type != ServiceFieldType.dataSource &&
              controller.isFieldVisible(p)) ...[
            _buildField(p, l10n),
            const SizedBox(height: 12),
          ],
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(l10n.leaveSubmit),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
    return AbsorbPointer(absorbing: _submitting, child: content);
  }

  Widget _errorState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.serviceFormSchemaFailed,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: _loadSchema, child: Text(l10n.retry)),
        ],
      ),
    );
  }

  /// 服务端带出的只读信息（User 身份字段）+ DataSource 取数（如辅导员）。
  /// DataSource 行的标签优先取 resultKey 配对字段的标签
  /// （'辅导员'，而非 '数据源-审批辅导员'）。
  Widget _buildInfoCard(AppLocalizations l10n) {
    final schema = _schema!;
    final controller = _controller!;
    final infoPlugins = schema.plugins.where(
      (p) =>
          p.type == ServiceFieldType.user &&
          !schema.isSuppressed(p.key) &&
          ((controller.values[p.key] ?? schema.data[p.key])
                  ?.toString()
                  .isNotEmpty ??
              false),
    );
    // setplugin 分发型 DataSource 不在信息卡展示（其效果经目标字段呈现，
    // 如 337 的年级）；单值型（辅导员）正常展示
    final dsPlugins = schema.dataSourcePlugins.where(
      (p) => p.dataSource?.isSetPlugin != true,
    );
    if (infoPlugins.isEmpty && dsPlugins.isEmpty) {
      return const SizedBox.shrink();
    }
    String dsLabel(ServiceFormPlugin p) {
      final ref = p.dataSource;
      if (ref != null && ref.resultKey.isNotEmpty && !ref.isSetPlugin) {
        final target = schema.pluginByKey(ref.resultKey);
        if (target != null && target.label.isNotEmpty) return target.label;
      }
      return controller.labelOf(p);
    }

    return CardWithTitle(
      title: l10n.leaveInfo,
      icon: const Icon(Icons.badge_outlined),
      child: Column(
        children: [
          for (final p in infoPlugins)
            _readonlyRow(
              controller.labelOf(p),
              controller.values[p.key]?.toString() ??
                  schema.data[p.key]?.toString() ??
                  '',
              iconForServiceFieldType(p.type),
            ),
          for (final p in dsPlugins)
            _readonlyRow(
              dsLabel(p),
              controller.values[p.key]?.toString() ?? '',
              iconForServiceFieldType(p.type),
            ),
        ],
      ),
    );
  }

  Widget _readonlyRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// 按字段类型分发渲染。
  Widget _buildField(ServiceFormPlugin p, AppLocalizations l10n) {
    final controller = _controller!;
    final required = controller.isFieldRequired(p.key);
    // 标签：服务端 label > override > key（labelOf 结果回填，卡片直接展示）
    final display = ServiceFormPlugin(
      key: p.key,
      type: p.type,
      label: controller.labelOf(p),
      sort: p.sort,
      options: p.options,
      hint: p.hint,
      maxCount: p.maxCount,
      dataSource: p.dataSource,
      raw: p.raw,
    );
    final resetKey = ValueKey('${p.key}#$_resetCounter');
    void setValue(Object? v) => setState(() => controller.values[p.key] = v);

    return switch (p.type) {
      ServiceFieldType.radio => ServiceRadioField(
        key: resetKey,
        plugin: display,
        value: controller.values[p.key]?.toString(),
        isRequired: required,
        onChanged: setValue,
      ),
      ServiceFieldType.select ||
      ServiceFieldType.selectV2 => ServiceSelectField(
        key: resetKey,
        plugin: display,
        value: controller.values[p.key]?.toString(),
        isRequired: required,
        hint: l10n.serviceFormSelectHint,
        onChanged: setValue,
      ),
      ServiceFieldType.checkbox => ServiceCheckboxField(
        key: resetKey,
        plugin: display,
        values: (controller.values[p.key] as Set<String>?) ?? const <String>{},
        isRequired: required,
        onChanged: setValue,
      ),
      ServiceFieldType.calendar => ServiceCalendarField(
        key: resetKey,
        plugin: display,
        value: controller.values[p.key] as DateTime?,
        isRequired: required,
        format: (d) => DateFormat('yyyy-MM-dd').format(d),
        onChanged: setValue,
      ),
      ServiceFieldType.region => ServiceRegionField(
        key: resetKey,
        plugin: display,
        value: controller.values[p.key] as ServiceRegionSelection?,
        isRequired: required,
        provinces: _regions,
        labels: ServiceRegionLabels(
          province: l10n.regionProvince,
          city: l10n.regionCity,
          area: l10n.regionArea,
          selectHint: l10n.regionSelectHint,
          detailHint: l10n.regionDetailHint,
          pickProvince: l10n.regionPickProvince,
          pickCity: l10n.regionPickCity,
          pickArea: l10n.regionPickArea,
        ),
        onChanged: setValue,
      ),
      ServiceFieldType.file => ServiceFileField(
        key: resetKey,
        plugin: display,
        files:
            (controller.values[p.key] as List?)?.whereType<File>().toList() ??
            const [],
        isRequired: required,
        hint: l10n.leaveAttachmentHint,
        addLabel: l10n.leaveAttachmentAdd,
        onChanged: setValue,
      ),
      ServiceFieldType.multiInput => ServiceMultiInputField(
        key: resetKey,
        plugin: display,
        initialValue: controller.values[p.key]?.toString() ?? '',
        isRequired: required,
        onChanged: setValue,
      ),
      _ => ServiceInputField(
        key: resetKey,
        plugin: display,
        initialValue: controller.values[p.key]?.toString() ?? '',
        isRequired: required,
        onChanged: setValue,
      ),
    };
  }
}
