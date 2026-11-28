import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_admin/admin_deletion_review_page.dart';
void main(){
 test('deletion requires reviewed, eligible and unprotected existing account',(){
  final data=<String,dynamic>{'status':'processing','account_exists':true,'protected_account':false,'eligible_for_clean_account_deletion':true,'execution_enabled':true};
  expect(AdminDeletionPolicy.canFinalize(data),isTrue);
  for(final key in ['account_exists','eligible_for_clean_account_deletion','execution_enabled']){
   expect(AdminDeletionPolicy.canFinalize({...data,key:false}),isFalse);
  }
  expect(AdminDeletionPolicy.canFinalize({...data,'protected_account':true}),isFalse);
  expect(AdminDeletionPolicy.canFinalize({...data,'status':'pending'}),isFalse);
  expect(AdminDeletionPolicy.canFinalize({}),isFalse);
 });
}
