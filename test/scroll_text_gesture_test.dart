import 'package:bugaoshan/app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 观测 AppScrollBehavior（dragDevices 加 mouse）与
/// SelectableText / TextField 的手势仲裁行为：
/// - 按住鼠标拖文本：应产生文本选择，父列表不应滚动；
/// - 按住鼠标拖空白区：列表应滚动（本次 PR 的目标能力）；
/// - 拖输入框：应是光标/选择，列表不应滚动。
void main() {
  Future<void> mouseDrag(
    WidgetTester tester,
    Offset start,
    Offset delta,
  ) async {
    final gesture =
        await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveBy(delta);
    await tester.pump();
    await gesture.moveBy(delta);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('SelectableText: mouse drag on text selects, list stays put',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: SelectableText(
                'hello selectable world this is a long line of text',
                style: TextStyle(fontSize: 18),
              ),
            ),
            Container(height: 600, color: Colors.blue),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    // 在文本上按住鼠标拖动 → 选区出现，列表不动
    final textTopLeft = tester.getTopLeft(find.byType(SelectableText));
    await mouseDrag(
        tester, textTopLeft + const Offset(30, 8), const Offset(60, 12));
    // ignore: avoid_print
    print('OBSERVE selectable-text-drag offset=${controller.offset}');

    final root = tester.renderObject(find.byType(EditableText));
    RenderEditable? findRenderEditable(RenderObject node) {
      if (node is RenderEditable) return node;
      RenderEditable? found;
      node.visitChildren((child) {
        found ??= findRenderEditable(child);
      });
      return found;
    }

    final renderEditable = findRenderEditable(root)!;
    // ignore: avoid_print
    print(
        'OBSERVE selection=${renderEditable.selection} offset=${controller.offset}');
    expect(renderEditable.selection?.isCollapsed, isFalse,
        reason: 'mouse drag on SelectableText should create a selection');
    expect(controller.offset, 0,
        reason: 'dragging on SelectableText must not scroll the list');

    // 在空白区（蓝色容器）按住鼠标拖动 → 列表滚动
    final blueCenter = tester.getCenter(find.byType(Container).last);
    await mouseDrag(tester, blueCenter, const Offset(0, -120));
    // ignore: avoid_print
    print('OBSERVE empty-area-drag offset=${controller.offset}');
    expect(controller.offset, greaterThan(0),
        reason: 'dragging on empty list area must scroll the list');
  });

  testWidgets('TextField: mouse drag inside field does not scroll list',
      (tester) async {
    final controller = ScrollController();
    final fieldFocus = FocusNode();
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                focusNode: fieldFocus,
                controller: TextEditingController(text: 'username here'),
              ),
            ),
            Container(height: 600, color: Colors.blue),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    // 在输入框内按住鼠标拖动 → 光标/选择，列表不动
    final fieldTopLeft = tester.getTopLeft(find.byType(TextField));
    await mouseDrag(
        tester, fieldTopLeft + const Offset(40, 20), const Offset(50, 4));
    // ignore: avoid_print
    print(
        'OBSERVE textfield-drag offset=${controller.offset} focused=${fieldFocus.hasFocus}');
    expect(controller.offset, 0,
        reason: 'dragging inside a TextField must not scroll the list');
    expect(fieldFocus.hasFocus, isTrue);

    // 在输入框外的空白区拖动 → 列表滚动
    final blueCenter = tester.getCenter(find.byType(Container).last);
    await mouseDrag(tester, blueCenter, const Offset(0, -120));
    // ignore: avoid_print
    print('OBSERVE textfield-empty-drag offset=${controller.offset}');
    expect(controller.offset, greaterThan(0),
        reason: 'dragging on empty list area must scroll the list');
  });

  testWidgets(
      'SingleChildScrollView + SelectableText (崩溃页同构): drag selects, empty area scrolls',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: SelectableText(
                  'stack trace line one\nstack trace line two\nline three',
                ),
              ),
              Container(height: 600, color: Colors.blue),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    final textTopLeft = tester.getTopLeft(find.byType(SelectableText));
    await mouseDrag(
        tester, textTopLeft + const Offset(30, 8), const Offset(60, 12));

    final root = tester.renderObject(find.byType(EditableText));
    RenderEditable? findRenderEditable(RenderObject node) {
      if (node is RenderEditable) return node;
      RenderEditable? found;
      node.visitChildren((child) {
        found ??= findRenderEditable(child);
      });
      return found;
    }

    final renderEditable = findRenderEditable(root)!;
    expect(renderEditable.selection?.isCollapsed, isFalse,
        reason: 'mouse drag on SelectableText should create a selection');
    expect(controller.offset, 0,
        reason: 'dragging on SelectableText must not scroll the list');

    final blueCenter = tester.getCenter(find.byType(Container).last);
    await mouseDrag(tester, blueCenter, const Offset(0, -120));
    expect(controller.offset, greaterThan(0),
        reason: 'dragging on empty area must scroll the view');
  });
}
