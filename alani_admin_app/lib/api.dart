import 'dart:convert';
import 'package:http/http.dart' as http;

/// The backend verifies Supabase Auth and shop ownership for every operation.
/// This app contains no service_role credential or private API key.
class AlAniAdminApi {
  AlAniAdminApi({http.Client? client}) : _client = client ?? http.Client();

  static const baseUrl = String.fromEnvironment(
    'ALANI_API_BASE',
    defaultValue: 'https://alani-site-admin-staging.up.railway.app',
  );

  final http.Client _client;
  String? _token;
  DateTime? _expiresAt;

  bool get signedIn => _token != null &&
      _expiresAt != null && DateTime.now().isBefore(_expiresAt!);

  void logOut() {
    _token = null;
    _expiresAt = null;
  }

  static List<String> nextStatuses(String current) => switch (current) {
    'placed' => const ['accepted','rejected'],
    'accepted' => const ['preparing'],
    'preparing' => const ['ready'],
    _ => const [],
  };

  static String statusLabel(String status) => switch (status) {
    'placed' => 'طلب جديد',
    'accepted' => 'مقبول',
    'preparing' => 'قيد التجهيز',
    'ready' => 'جاهز للتسليم',
    'rejected' => 'مرفوض',
    'cancelled' => 'ملغي',
    _ => status,
  };

  static String kindLabel(String kind) => switch (kind) {
    'video' => 'فيديو',
    'recipe' => 'وصفة',
    'article' => 'مقال',
    'post' => 'منشور',
    _ => kind,
  };

  Future<dynamic> _request(String route, {Map<String,dynamic>? body,
      String method='GET', bool authenticated=true}) async {
    if (authenticated && !signedIn) {
      throw StateError('انتهت جلسة المدير. سجّل الدخول من جديد.');
    }
    final uri = Uri.parse('$baseUrl$route');
    if (uri.scheme!='https') throw StateError('يتطلب الاتصال HTTPS.');
    final headers = <String,String>{
      'accept':'application/json',
      'content-type':'application/json',
      if (authenticated) 'authorization':'Bearer $_token',
    };
    final response = await _client.send(http.Request(method,uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body ?? {}))
      .timeout(const Duration(seconds:18));
    final data = await http.Response.fromStream(response);
    dynamic parsed;
    try { parsed = jsonDecode(data.body); } catch (_) { parsed={}; }
    if (data.statusCode<200 || data.statusCode>=300) {
      final message=parsed is Map ? parsed['error']?.toString() : null;
      throw StateError(message ?? 'فشل الاتصال بالخادم (رمز: ${data.statusCode})');
    }
    return parsed;
  }

  Future<void> login(String email,String password) async {
    logOut();
    final result = await _request('/api/login',
      method:'POST',
      authenticated:false,
      body:{'email':email.trim(),'password':password},
    ) as Map<String,dynamic>;
    final access = result['access_token'];
    if (access is! String || access.isEmpty) throw StateError('لم تصل جلسة صالحة.');
    _token=access;
    final seconds=(result['expires_in'] as num?)?.toInt() ?? 3600;
    _expiresAt=DateTime.now().add(Duration(seconds:seconds));
    try {
      await overview();
    } catch (_) {
      logOut();
      rethrow;
    }
  }

  Future<Map<String,dynamic>> overview() async {
    final data=await _request('/api/admin/overview');
    return Map<String,dynamic>.from(data as Map);
  }

  Future<void> saveProduct(Map<String,dynamic> values) async {
    await _request('/api/admin/product',method:'POST',body:values);
  }

  Future<void> changeOrder(String orderId,String status) async {
    await _request('/api/admin/order',method:'POST',
      body:{'id':orderId,'status':status});
  }

  Future<void> savePost(Map<String,dynamic> values) async {
    await _request('/api/admin/post',method:'POST',body:values);
  }

  void dispose() => _client.close();
}
