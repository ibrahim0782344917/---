import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_campaign_banner.dart';

void main() {
  test('banner is visible only inside approved UTC time window', () {
    final start=DateTime.utc(2026,11,20,8);
    final end=DateTime.utc(2026,11,22,8);
    expect(AlAniCampaignWindow.visible(start,end,DateTime.utc(2026,11,20,7,59)),isFalse);
    expect(AlAniCampaignWindow.visible(start,end,start),isTrue);
    expect(AlAniCampaignWindow.visible(start,end,DateTime.utc(2026,11,21)),isTrue);
    expect(AlAniCampaignWindow.visible(start,end,end),isFalse);
    expect(AlAniCampaignWindow.visible(end,start,end),isFalse);
  });
}
