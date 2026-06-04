import 'package:flutter_test/flutter_test.dart';

import 'package:javbus/src/app.dart';

void main() {
  testWidgets('shows the compact search shell and settings plugin entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MagnetFinderApp());
    await tester.pump();

    expect(find.text('输入番号、标题或关键词'), findsOneWidget);
    expect(find.text('磁力'), findsWidgets);
    expect(find.text('收藏'), findsWidgets);
    expect(find.text('搜盘'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('插件'), findsNothing);

    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('显示模式'), findsOneWidget);
    expect(find.text('插件目录'), findsOneWidget);
    expect(find.text('插件协议'), findsOneWidget);

    await tester.tap(find.text('插件目录'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('搜索已加载插件'), findsOneWidget);
    expect(find.text('安装 JSON'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });
}
