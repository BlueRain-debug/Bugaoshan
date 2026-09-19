import 'package:bugaoshan/services/auth/scu_exceptions.dart';

/// `code` 字段视为「成功」的取值（实测是字符串 `"0"`，同时兼容数字与大小写变体）。
const Set<String> _kSuccessCodes = {'0', '200', 'success', 'true'};

/// 研教务 / EMAP（金智 WiseDU）统一响应信封解包。
///
/// 实测响应形如：
/// ```json
/// {"code":"0","datas":{"cspzcx":{"totalSize":1045,"pageSize":15,
///   "rows":[{"CSDM":"bbgl_zzfw_appid","CSMC":"自助服务-appId","CSZ":null}],
///   "extParams":{"code":1,"totalPage":0,"logId":"db11466e…"}}}}
/// ```
///
/// 三个必须注意的坑：
/// 1. `code` 是**字符串** `"0"`，不是数字 → 判定成功前先归一化。
/// 2. `datas` 的键名是**查询动作名**（这里是 `cspzcx`），调用方无法预知，
///    所以只能「找出 `datas` 里那个带 `rows` 的 Map」，不能硬编码键名。
///    同一信封里有多个 `rows` 时取第一个。
/// 3. 行内字段是**全大写数据库列名**且大量为 `null`，取值须走
///    `lib/utils/json_utils.dart` 的 `safe*` helper。
///
/// 直接返回数组的非信封接口原样透传；函数幂等（对已解包的结果再调用无副作用）。
/// `code` 非成功值时抛 [ServiceException]（不是 [UnauthenticatedException]：
/// 会话失效时服务端返回的是登录页 HTML，走不到 JSON 解码这一步）。
Object? unwrapGsEnvelope(Object? json) {
  if (json is! Map) return json;

  final code = json['code'];
  if (code != null && !_isSuccessCode(code)) {
    throw ServiceException('研教务返回错误（code=$code）');
  }

  final rows = _findRows(json);
  if (rows != null) return rows;

  final datas = json['datas'];
  if (datas is List) return datas;
  return json;
}

/// 解包并规整为「行列表」，供各 `listFromJson` / 解析器直接消费。
///
/// 非列表负载（含无法识别结构的信封）一律返回空列表，保证脏数据不崩溃。
List<Map<String, dynamic>> gsRows(Object? json) {
  final payload = unwrapGsEnvelope(json);
  if (payload is! List) return const [];
  return payload.whereType<Map<String, dynamic>>().toList();
}

bool _isSuccessCode(Object code) =>
    _kSuccessCodes.contains(code.toString().trim().toLowerCase());

/// 递归找 `rows`：信封键名不可预知，而嵌套深度是
/// `根 → datas → <动作名> → rows`，所以只能逐层下探。
///
/// [maxDepth] 防止异常深的结构拖垮解析。
List<Object?>? _findRows(Object? node, [int depth = 0]) {
  if (node is! Map || depth > _maxEnvelopeDepth) return null;
  final direct = node['rows'];
  if (direct is List) return direct;
  for (final value in node.values) {
    final found = _findRows(value, depth + 1);
    if (found != null) return found;
  }
  return null;
}

const int _maxEnvelopeDepth = 4;
