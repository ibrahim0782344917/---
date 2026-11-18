import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_admin/alani_legacy_customers_import_page.dart';

void main(){
  test('CSV file preserves Arabic quoted values and avoids column drift',(){
    const input='source_serial,recipient_name,phone_primary,phone_secondary,historical_order_count,governorate,district,address_details,goods_type,source_row\n'
      '1,"مستلم, تجريبي",07812345678,,3,بغداد,اختبار,"شقة 1, بناية 2",عسل,2\n';
    final parsed=LegacyCustomerCsv.parse(input);
    expect(LegacyCustomerCsv.matchesHeader(parsed.first),true);
    expect(parsed.length,2);
    expect(parsed[1][1],'مستلم, تجريبي');
    expect(parsed[1][7],'شقة 1, بناية 2');
    expect(LegacyCustomerCsv.isIraqiMobile(parsed[1][2]),true);
  });
  test('Import preview rejects structurally wrong headers',(){
    expect(LegacyCustomerCsv.matchesHeader(['name','phone']),false);
    expect(LegacyCustomerCsv.isIraqiMobile('987654321'),false);
    expect(LegacyCustomerCsv.isIraqiMobile('07812345678'),true);
  });
}
