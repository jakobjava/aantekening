import 'package:aantekening/src/ai/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sums of money are said as short as says them', () {
    expect(dollars(5), r'$5');
    expect(dollars(2.5), r'$2.50');
    expect(dollars(0.28), r'$0.28');
    expect(dollars(0.05), r'$0.05');
    expect(dollars(0.0013), r'$0.0013');
    expect(dollars(0.00134), r'$0.0013');
    expect(dollars(0.00001), r'under $0.0001');
    expect(costNote(0.0013), r'≈ $0.0013');
    expect(costNote(0), isNull, reason: 'a model on this computer');
    expect(costNote(null), isNull, reason: 'a price not known');
  });
}
