import 'dart:convert';
import 'package:bugaoshan/services/auth/gs_auth.dart';
import 'package:bugaoshan/services/auth/scu_exceptions.dart';
import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/utils/constants.dart';
import 'package:bugaoshan/utils/graduate_schedule_parser.dart';
import 'package:bugaoshan/utils/gs_json_envelope.dart';

/// 研教务（gsapp / EMAP）API 服务（第1层）。
///
/// 通过 [GsAuth] 获取的 CookieClient 访问研教务接口。响应信封已实测确认
/// （见 [unwrapGsEnvelope]）：`{"code":"0","datas":{"<动作名>":{"rows":[…]}}}`
/// —— [_postForm] 统一解包后交给各解析器。
///
/// 课表链路（2026-09-15 登录抓包实测定案，见 `.tmp/gs/findings.md` §8）：
/// - 课表 `POST xspkjgcx.do`，body `XNXQDM=<学期5位码>&*order=-ZCBH`，
///   行字段 KCMC/JSXM/JASMC/XQ(星期,周一=1)/KSJCDM/JSJCDM/ZCMC；
/// - 学期列表 `kfdxnxqcx.do`、首次上课日期 `xsjxrwcx.do`（SCSKRQ）。
///
/// 成绩 / 培养计划的 `.do` 端点尚未定案，对应方法随功能一并添加
/// （应用入口：成绩 `/sys/wdcjapp/*default/index.do`、
/// 培养计划 `/sys/wdpyjhapp/*default/index.do`、
/// 培养方案 `/sys/wdpyfaappscu/*default/index.do#/pyfaxq`）。
class GsApiService {
  GsApiService(this._gsAuth);

  static const String _tag = 'GsApiService';

  final GsAuth _gsAuth;

  /// 研究生课表（供课表导入，直连）。
  ///
  /// [xnxqdm] 缺省时自动取最新学期码（[fetchSemesters] 的最大值）；
  /// 获取学期码失败则传空让服务端按会话默认（与页面初次加载一致）。
  Future<List<Course>> fetchSchedule({String? xnxqdm}) async {
    final term = xnxqdm ?? await latestSemesterCode() ?? '';
    final rows = await _postForm(kGsScheduleEndpointPath, {
      'XNXQDM': term,
      '*order': '-ZCBH',
    });
    return graduateCoursesFromJson(rows);
  }

  /// 学期码列表（kfdxnxqcx.do），按码值降序（最大 = 最新学期）。
  ///
  /// 响应行结构未逐字段核实，这里只宽松抽取形如 5 位数字的学期码
  /// （候选键 XNXQDM/DM/NXQDM/WID）。
  Future<List<String>> fetchSemesters() async {
    final rows = await _postForm(kGsSemesterListPath, const {});
    final codePattern = RegExp(r'^\d{5}$');
    final codes = <String>{};
    for (final row in rows) {
      for (final key in const ['XNXQDM', 'DM', 'NXQDM', 'WID']) {
        final value = row[key]?.toString();
        if (value != null && codePattern.hasMatch(value)) {
          codes.add(value);
          break;
        }
      }
    }
    final sorted = codes.toList()..sort();
    return sorted.reversed.toList();
  }

  /// 最新学期码；学期列表不可用时返回 null（调用方回退到服务端默认学期）。
  Future<String?> latestSemesterCode() async {
    try {
      final semesters = await fetchSemesters();
      return semesters.isEmpty ? null : semesters.first;
    } catch (e) {
      AppLog.w(_tag, 'latestSemesterCode: $e');
      return null;
    }
  }

  /// 首次上课日期行（SCSKRQ / PKSJ），供学期第 1 周周一反推，
  /// 见 [semesterStartMondayFromFirstClassRows]。
  Future<List<Map<String, dynamic>>> fetchFirstClassRows(
    String xnxqdm,
  ) async {
    return _postForm(kGsFirstClassPath, {
      'XNXQDM': xnxqdm,
      'XH': '',
      'pageNumber': '1',
      'pageSize': '20',
    });
  }

  /// 用 cookie 客户端 POST 表单到 ehall 域的 `.do` 接口，解包信封为行列表。
  ///
  /// - 401/403 → [UnauthenticatedException]；
  /// - 响应不是 JSON（会话失效时服务端给的是统一认证登录页 HTML）→ 记警告并
  ///   返回空列表，既避免页面崩溃，也让 UI 落到「无数据」态；
  /// - 信封 `code` 非成功值 → 由 [unwrapGsEnvelope] 抛 [ServiceException]，
  ///   这里**不吞**该异常。
  Future<List<Map<String, dynamic>>> _postForm(
    String path,
    Map<String, String> fields,
  ) async {
    final client = await _gsAuth.getClient();
    final response = await client.post(
      Uri.parse('$kGsEhallBaseUrl$path'),
      headers: {'Accept': 'application/json, text/javascript, */*; q=0.01'},
      body: fields,
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const UnauthenticatedException();
    }
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw ServiceException('研教务请求失败', statusCode: response.statusCode);
    }
    if (response.body.isEmpty) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      AppLog.w(_tag, '$path 响应非 JSON（len=${response.body.length}），会话可能已失效');
      return const [];
    }
    return gsRows(decoded);
  }
}
