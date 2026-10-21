import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_reading/services/text_loader.dart';

void main() {
  test('Paginator：分页拼接等于原文（中英混合/空行/长行）', () async {
    final sb = StringBuffer();
    for (var i = 0; i < 5000; i++) {
      sb.write('第$i章：测试文本Test内容，包含一些长句子和标点符号。\n\n');
      if (i % 7 == 0) {
        sb.write('空行后面是英文段落 mixed english text with spaces here.\n');
      }
    }
    final text = sb.toString();
    final p = Paginator(
      text: text,
      width: 360,
      height: 640,
      style: const TextStyle(fontSize: 18, height: 1.7),
    );
    while (!p.complete) {
      await p.nextBatch(maxPages: 256);
    }
    expect(p.pageCount, greaterThan(0));
    expect(p.pages.join(), text, reason: '分页结果拼接必须等于原文');
  });

  test('Paginator：3MB 级文本快速完成且拼接等于原文', () async {
    const unit = '中文小说正文内容，混杂 punctuation 与空格 mixed words。';
    const count = 120000;
    final text = List.filled(count, unit).join();
    expect(text.length, greaterThan(3000000));

    final sw = Stopwatch()..start();
    final p = Paginator(
      text: text,
      width: 360,
      height: 640,
      style: const TextStyle(fontSize: 18, height: 1.7),
    );
    while (!p.complete) {
      await p.nextBatch(maxPages: 100000);
    }
    sw.stop();
    expect(p.pages.join(), text);
    // 字符宽度估算排版应为 O(n)，3MB 不应超过 10 秒（实际 <1 秒）。
    expect(sw.elapsedMilliseconds, lessThan(10000),
        reason: '排版耗时 ${sw.elapsedMilliseconds}ms');
  });
}
