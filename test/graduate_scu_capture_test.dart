import 'package:flutter_test/flutter_test.dart';
import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/utils/graduate_schedule_parser.dart';

/// 川大研究生课表（ehall wdkbapp `xspkjgcx.do`）真实信封/字段形状测试。
///
/// 字段结构 2026-09-15 登录抓包实测定案（见 `.tmp/gs/findings.md` §8）：
/// 信封 `datas.<动作名>.rows`，行字段为大写 EMAP 列名（KCMC/JSXM/JASMC/
/// XQ/KSJCDM/JSJCDM/ZCMC），每行 = 一节课。数据已脱敏：
/// 课程 / 教师 / 教室均为虚构，仅保留结构与取值格式。
void main() {
  const payload =
      '{"code":"0","datas":{"xspkjgcx":{"totalSize":3,"rows":['
      '{"KCMC":"测试课程一","JSXM":"张老师","JASMC":"望江研究生楼一区204",'
      '"XQ":1,"KSJCDM":2,"JSJCDM":3,"ZCMC":"2-17周","KSSJ":855,"JSSJ":1040,"XNXQDM":"20261"},'
      '{"KCMC":"测试课程二","JSXM":"李老师","JASMC":"望江三教150",'
      '"XQ":3,"KSJCDM":5,"JSJCDM":7,"ZCMC":"1-16周(单)","XNXQDM":"20261"},'
      '{"KCMC":"测试课程三","JSXM":"王老师","JASMC":"江安楼C101",'
      '"XQ":7,"KSJCDM":1,"JSJCDM":2,"ZCMC":"3-18周","XNXQDM":"20261"}'
      ']},"extParams":{"code":1,"totalPage":0,"logId":"test"}}}';

  group('川大研究生课表行（大写 EMAP 字段）', () {
    test('信封解包 + 节次起止 + 周次文本解析', () {
      final courses = graduateCoursesFromCapturedJson([payload]);
      expect(courses, hasLength(3));

      final first = courses.firstWhere((c) => c.name == '测试课程一');
      expect(first.teacher, '张老师');
      expect(first.location, '望江研究生楼一区204');
      expect(first.dayOfWeek, 1);
      expect(first.startSection, 2);
      expect(first.endSection, 3);
      expect(first.startWeek, 2);
      expect(first.endWeek, 17);
      expect(first.weekType, WeekType.every);

      final odd = courses.firstWhere((c) => c.name == '测试课程二');
      expect(odd.dayOfWeek, 3);
      expect(odd.startSection, 5);
      expect(odd.endSection, 7);
      expect(odd.weekType, WeekType.odd);

      final sunday = courses.firstWhere((c) => c.name == '测试课程三');
      expect(sunday.dayOfWeek, 7);
      expect(sunday.startWeek, 3);
      expect(sunday.endWeek, 18);
    });
  });

  group('相邻节次合并', () {
    test('同课名同周次同地点的连续节次合并为一条', () {
      final payload =
          '{"code":"0","datas":{"xspkjgcx":{"rows":['
          '{"KCMC":"测试课程一","JSXM":"张老师","JASMC":"教学楼204","XQ":1,"KSJCDM":2,"JSJCDM":2,"ZCMC":"2-17周"},'
          '{"KCMC":"测试课程一","JSXM":"张老师","JASMC":"教学楼204","XQ":1,"KSJCDM":3,"JSJCDM":3,"ZCMC":"2-17周"},'
          '{"KCMC":"测试课程一","JSXM":"张老师","JASMC":"教学楼204","XQ":1,"KSJCDM":4,"JSJCDM":4,"ZCMC":"2-17周"}'
          ']}}}';
      final courses = graduateCoursesFromCapturedJson([payload]);
      expect(courses, hasLength(1));
      expect(courses.first.startSection, 2);
      expect(courses.first.endSection, 4);
      expect(courses.first.dayOfWeek, 1);
    });

    test('中间隔节的不合并', () {
      final payload =
          '{"code":"0","datas":{"xspkjgcx":{"rows":['
          '{"KCMC":"测试课程一","JSXM":"张老师","JASMC":"教学楼204","XQ":2,"KSJCDM":2,"JSJCDM":2,"ZCMC":"2-17周"},'
          '{"KCMC":"测试课程一","JSXM":"张老师","JASMC":"教学楼204","XQ":2,"KSJCDM":4,"JSJCDM":4,"ZCMC":"2-17周"}'
          ']}}}';
      final courses = graduateCoursesFromCapturedJson([payload]);
      expect(courses, hasLength(2));
      expect(courses.map((c) => c.startSection), [2, 4]);
    });

    test('周次或教师不同不合并（同一门课两段式上课）', () {
      final payload =
          '{"code":"0","datas":{"xspkjgcx":{"rows":['
          '{"KCMC":"测试课程一","JSXM":"张老师","JASMC":"教学楼204","XQ":2,"KSJCDM":1,"JSJCDM":2,"ZCMC":"3-7周"},'
          '{"KCMC":"测试课程一","JSXM":"李老师","JASMC":"教学楼204","XQ":2,"KSJCDM":1,"JSJCDM":2,"ZCMC":"8-14周"}'
          ']}}}';
      final courses = graduateCoursesFromCapturedJson([payload]);
      expect(courses, hasLength(2));
      expect(courses.map((c) => c.teacher), ['张老师', '李老师']);
      expect(courses.map((c) => c.startWeek), [3, 8]);
    });
  });

  group('按课程名配色', () {
    test('同名课程同色，不同课程不同色', () {
      final payload =
          '{"code":"0","datas":{"xspkjgcx":{"rows":['
          '{"KCMC":"测试课程一","JSXM":"张老师","JASMC":"教学楼204","XQ":1,"KSJCDM":2,"JSJCDM":3,"ZCMC":"2-17周"},'
          '{"KCMC":"测试课程一","JSXM":"李老师","JASMC":"教学楼204","XQ":1,"KSJCDM":2,"JSJCDM":3,"ZCMC":"8-14周"},'
          '{"KCMC":"测试课程二","JSXM":"王老师","JASMC":"教学楼305","XQ":3,"KSJCDM":5,"JSJCDM":6,"ZCMC":"1-16周"}'
          ']}}}';
      final courses = graduateCoursesFromCapturedJson([payload]);
      expect(courses, hasLength(3));
      // 两段式上课的同一门课（不同周次/教师）颜色一致
      expect(courses[0].colorValue, courses[1].colorValue);
      expect(courses[0].colorValue, isNot(courses[2].colorValue));
      expect(courses[0].colorValue, isNot(0));
    });
  });

  group('学期第 1 周周一反推（SCSKRQ + PKSJ）', () {
    test('首课即周一：第1周周一 = 首课日 − (起始周−1)×7', () {
      final start = semesterStartMondayFromFirstClassRows([
        {
          'SCSKRQ': '2026-09-14',
          'PKSJ': '3-14周 星期一[05-08节]',
          'XNXQDM': '20261',
        },
      ]);
      expect(start, DateTime(2026, 8, 31));
    });

    test('首课非周一时对齐到当周周一', () {
      final start = semesterStartMondayFromFirstClassRows([
        {'SCSKRQ': '2026-09-16', 'PKSJ': '3-13周 星期三[05-07节]'},
      ]);
      expect(start, DateTime(2026, 8, 31));
    });

    test('多行投票取众数，脏行安全忽略', () {
      final start = semesterStartMondayFromFirstClassRows([
        {'SCSKRQ': '2026-09-14', 'PKSJ': '3-14周 星期一[05-08节]'},
        {'SCSKRQ': '2026-09-16', 'PKSJ': '3-13周 星期三[05-07节]'},
        {'SCSKRQ': '不是日期', 'PKSJ': '2-5周'},
        {'PKSJ': '3-14周'},
        {'SCSKRQ': '2026-09-14'},
      ]);
      expect(start, DateTime(2026, 8, 31));
    });

    test('无有效行时返回 null', () {
      expect(semesterStartMondayFromFirstClassRows(const []), isNull);
      expect(
        semesterStartMondayFromFirstClassRows([
          {'SCSKRQ': '2026-09-14'},
        ]),
        isNull,
      );
    });
  });
}
