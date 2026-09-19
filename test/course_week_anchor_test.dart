import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/utils/semester_week.dart';
import 'package:flutter_test/flutter_test.dart';

/// 教学周 ↔ 自然日 的口径回归测试。
///
/// 校历的教学周以周日为首日成行，**第 1 周是包含学期起点的那一周**：
/// 学期起点为周一时（2026-08-31），第 1 周为 8/30(日)~9/5(六)，故 9/20(日) 属第 4 周。
/// 课表页 `dateForCourseDay`、桌面小组件、顶栏/校历徽标、设置页「当前周」都必须取自
/// `utils/semester_week.dart` 的同一口径——2026-09-19 的线上问题正是小组件按「自起点
/// 起算的整 7 天块」把 9/20 算成第 3 周，查不到那天周日的课。
void main() {
  group('courseWeekAnchor', () {
    test('周一起点：块首日是起点前一天（周日）', () {
      expect(courseWeekAnchor(DateTime(2026, 8, 31)), DateTime(2026, 8, 30));
    });

    test('周日起点：块首日即起点本身', () {
      expect(courseWeekAnchor(DateTime(2026, 3, 8)), DateTime(2026, 3, 8));
      expect(courseWeekAnchor(DateTime(2026, 2, 22)), DateTime(2026, 2, 22));
    });
  });

  group('courseWeekOf', () {
    test('周一起点的学期：9/20(日) 属第 4 周', () {
      final start = DateTime(2026, 8, 31);

      expect(courseWeekOf(start, DateTime(2026, 8, 31)), 1); // 第 1 周 周一
      expect(courseWeekOf(start, DateTime(2026, 9, 5)), 1); // 第 1 周 周六
      expect(courseWeekOf(start, DateTime(2026, 9, 6)), 2); // 第 2 周 周日
      expect(courseWeekOf(start, DateTime(2026, 9, 13)), 3);
      expect(courseWeekOf(start, DateTime(2026, 9, 19)), 3); // 今天（周六）
      expect(courseWeekOf(start, DateTime(2026, 9, 20)), 4); // 明天（周日）
      expect(courseWeekOf(start, DateTime(2026, 9, 21)), 4);
    });

    test('周日起点的学期：与「自起点起算的整 7 天块」一致', () {
      final start = DateTime(2026, 3, 8);

      expect(courseWeekOf(start, DateTime(2026, 3, 8)), 1);
      expect(courseWeekOf(start, DateTime(2026, 3, 14)), 1);
      expect(courseWeekOf(start, DateTime(2026, 3, 15)), 2);
      expect(courseWeekOf(start, DateTime(2026, 3, 21)), 2);
    });

    test('早于块首日的日期一律算第 1 周', () {
      expect(courseWeekOf(DateTime(2026, 8, 31), DateTime(2026, 8, 25)), 1);
    });
  });

  group('与课表页列日期同口径', () {
    test('任意起点星期 + 任意周次：dateForCourseDay 的结果反算周次恒等于入参', () {
      for (var offset = 0; offset < 7; offset++) {
        final start = DateTime(2026, 8, 31).add(Duration(days: offset));
        final config = ScheduleConfig(
          semesterStartDate: start,
          semesterName: 'test',
        );
        for (var week = 1; week <= 6; week++) {
          for (var dayOfWeek = 1; dayOfWeek <= 7; dayOfWeek++) {
            final date = config.dateForCourseDay(week, dayOfWeek);
            expect(
              courseWeekOf(start, date),
              week,
              reason: '起点=$start 周=$week 星期=$dayOfWeek → $date',
            );
          }
        }
      }
    });
  });
}
