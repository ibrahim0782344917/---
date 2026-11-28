import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_admin/admin_mfa_page.dart';

void main() {
  test('production administrator requires AAL2 when enabled', () {
    expect(AdminMfaPolicy.needsChallenge(enabled:true,url:AdminMfaPolicy.productionUrl,aal2:false),isTrue);
    expect(AdminMfaPolicy.needsChallenge(enabled:true,url:AdminMfaPolicy.productionUrl,aal2:true),isFalse);
    expect(AdminMfaPolicy.needsChallenge(enabled:false,url:AdminMfaPolicy.productionUrl,aal2:false),isFalse);
    expect(AdminMfaPolicy.needsChallenge(enabled:true,url:'https://test.supabase.co',aal2:false),isFalse);
  });
  test('authenticator codes require exactly six ASCII digits', () {
    expect(AdminMfaPolicy.validCode('123456'),isTrue);
    for(final value in ['','12345','1234567','123abc',' 123456']) {
      expect(AdminMfaPolicy.validCode(value),isFalse);
    }
  });
}
