import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Private support chat is deliberately restricted to the isolated test DB.
/// Push notifications and presence are NOT part of this feature.
abstract final class AlAniSupportFeature {
  static const bool enabled =
      bool.fromEnvironment('ALANI_SUPPORT_CHAT_ENABLED', defaultValue: false) &&
      (String.fromEnvironment('SUPABASE_URL') ==
              'https://tgvdwotbrnhcoykuxdpr.supabase.co' ||
          bool.fromEnvironment(
            'ALANI_SUPPORT_PRODUCTION_APPROVED', defaultValue: false));
  static const String storeId = '25091ca2-c0da-416c-b634-81b188ee66be';
}

/// Customer creates or retrieves exactly one private conversation with the
/// approved store. Phone numbers and user profiles are never queried.
class AlAniCustomerSupportPage extends StatefulWidget {
  const AlAniCustomerSupportPage({super.key});

  @override
  State<AlAniCustomerSupportPage> createState() =>
      _AlAniCustomerSupportPageState();
}

class _AlAniCustomerSupportPageState
    extends State<AlAniCustomerSupportPage> {
  String? _threadId;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    if (!AlAniSupportFeature.enabled) {
      setState(() {
        _loading = false;
        _error = 'الدردشة قيد الاختبار وليست مفعّلة على الإنتاج.';
      });
      return;
    }
    if (Supabase.instance.client.auth.currentUser == null) {
      setState(() {
        _loading = false;
        _error = 'سجّل الدخول بحساب الزبون لفتح محادثة خاصة.';
      });
      return;
    }
    try {
      final id = await Supabase.instance.client.rpc(
        'alani_open_support_thread');
      if (mounted) setState(() {
        _threadId = id.toString();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'تعذّر فتح المحادثة. جرّب مرة ثانية.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('التواصل مع المتجر')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _threadId != null
            ? AlAniConversation(threadId: _threadId!)
            : Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error ?? 'تعذّر فتح المحادثة.',
                    textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(() { _loading = true; _error = null; });
                      _open();
                    },
                    child: const Text('إعادة المحاولة'),
                  ),
                ]),
              )),
  );
}

class AlAniSupportInboxPage extends StatefulWidget {
  const AlAniSupportInboxPage({super.key});
  @override
  State<AlAniSupportInboxPage> createState() =>
      _AlAniSupportInboxPageState();
}

class _AlAniSupportInboxPageState extends State<AlAniSupportInboxPage> {
  List<Map<String, dynamic>> threads = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AlAniSupportFeature.enabled) {
      setState(() {
        loading = false;
        error = 'محادثات العملاء غير مفعّلة على الإنتاج.';
      });
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('alani_support_threads')
          .select('id,updated_at')
          .eq('store_id', AlAniSupportFeature.storeId)
          .order('updated_at', ascending: false)
          .limit(60);
      if (mounted) setState(() {
        threads = rows.map((x) => Map<String, dynamic>.from(x)).toList();
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted) setState(() {
        loading = false;
        error = 'تعذّر تحميل محادثات متجرك؛ تأكد من صلاحيات الحساب.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('محادثات الدعم'),
      actions: [IconButton(
        tooltip: 'تحديث',
        onPressed: _load,
        icon: const Icon(Icons.refresh),
      )]),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
            ? Center(child: Text(error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: threads.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 85),
                        Center(child: Text('لا توجد محادثات بعد.')),
                      ])
                    : ListView.builder(
                        itemCount: threads.length,
                        itemBuilder: (context, index) {
                          final thread = threads[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.support_agent_outlined)),
                            title: Text('محادثة زبون #${index + 1}'),
                            subtitle: const Text(
                              'المحادثات خاصة؛ لا تظهر أرقام الهاتف'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text(
                                      'محادثة خاصة')),
                                  body: AlAniConversation(
                                    threadId: thread['id'].toString(),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
  );
}

/// Participant-only messages. The database validates the current user and
/// limits messages per minute. Polling is a fallback, not push notifications.
class AlAniConversation extends StatefulWidget {
  const AlAniConversation({super.key, required this.threadId});
  final String threadId;
  @override
  State<AlAniConversation> createState() => _AlAniConversationState();
}

class _AlAniConversationState extends State<AlAniConversation> {
  final controller = TextEditingController();
  final scroller = ScrollController();
  Timer? poller;
  List<Map<String, dynamic>> messages = [];
  bool submitting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _refresh();
    poller = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    poller?.cancel();
    scroller.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!AlAniSupportFeature.enabled) return;
    try {
      final rows = await Supabase.instance.client
          .from('alani_support_messages')
          .select('id,sender_id,body,created_at')
          .eq('thread_id', widget.threadId)
          .order('created_at', ascending: true)
          .limit(100);
      if (!mounted) return;
      final hadCount = messages.length;
      setState(() {
        messages = rows.map((x) => Map<String, dynamic>.from(x)).toList();
        error = null;
      });
      if (messages.length != hadCount) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroller.hasClients) {
            scroller.jumpTo(scroller.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() =>
          error = 'تعذّر تحديث الرسائل. تأكد من الاتصال والصلاحيات.');
    }
  }

  Future<void> _send() async {
    final body = controller.text.trim();
    if (!AlAniSupportFeature.enabled ||
        submitting || body.isEmpty || body.length > 1500) return;
    setState(() => submitting = true);
    try {
      await Supabase.instance.client.rpc('alani_send_support_message',
        params: {'p_thread_id': widget.threadId, 'p_body': body});
      controller.clear();
      await _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'لم تُرسل الرسالة؛ تحقق من الحساب أو حد الإرسال.')));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    return Column(children: [
      const Padding(
        padding: EdgeInsets.all(10),
        child: Text('مراسلة خاصة مع فريق المتجر. الرد ليس فورياً؛ '
            'الإشعارات الفورية قيد التجهيز.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
      ),
      if (error != null)
        TextButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: Text(error!),
        ),
      Expanded(
        child: messages.isEmpty
            ? const Center(child: Text('ابدأ المحادثة برسالتك الأولى.'))
            : ListView.builder(
                controller: scroller,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final mine = msg['sender_id']?.toString() == me;
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 310),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: mine
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(msg['body']?.toString() ?? '',
                        textDirection: TextDirection.rtl),
                    ),
                  );
                },
              ),
      ),
      SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 12),
        child: Row(children: [
          Expanded(child: TextField(
            controller: controller,
            maxLength: 1500,
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'اكتب رسالتك...',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          )),
          const SizedBox(width: 7),
          IconButton.filled(
            tooltip: 'إرسال الرسالة',
            onPressed: submitting ? null : _send,
            icon: submitting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
          ),
        ]),
      )),
    ]);
  }
}
