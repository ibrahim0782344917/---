import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Private support chat is deliberately restricted to the isolated test DB.
/// Foreground realtime + polling. Push notifications are not yet configured.
abstract final class AlAniSupportFeature {
  static const bool enabled =
      bool.fromEnvironment('ALANI_SUPPORT_CHAT_ENABLED', defaultValue: false) &&
      (String.fromEnvironment('SUPABASE_URL') ==
              'https://tgvdwotbrnhcoykuxdpr.supabase.co' ||
          bool.fromEnvironment(
            'ALANI_SUPPORT_PRODUCTION_APPROVED', defaultValue: false));
  static const bool liveTest = enabled &&
      String.fromEnvironment('SUPABASE_URL') == 'https://tgvdwotbrnhcoykuxdpr.supabase.co';
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
  bool _loadingNow = false;
  Timer? _inboxPoller;
  RealtimeChannel? _inboxChannel;
  StreamSubscription<AuthState>? _inboxAuth;
  String? _inboxActor;

  @override
  void initState() {
    super.initState();
    if (AlAniSupportFeature.enabled) {
      final db=Supabase.instance.client;
      _inboxActor=db.auth.currentUser?.id;
      _inboxAuth=db.auth.onAuthStateChange.listen((_) {
        if(mounted && db.auth.currentUser?.id!=_inboxActor) {
          setState(() {threads=[]; loading=false; error='تغيّر الحساب؛ أعد فتح صندوق الدعم.';});
        }
      });
      if(AlAniSupportFeature.liveTest) {
        _inboxChannel=db.channel('support-inbox-${identityHashCode(this)}')
          .onPostgresChanges(event:PostgresChangeEvent.insert,schema:'public',table:'alani_support_threads',callback:(_){unawaited(_load());})
          .onPostgresChanges(event:PostgresChangeEvent.update,schema:'public',table:'alani_support_threads',callback:(_){unawaited(_load());})
          .subscribe();
        _inboxPoller=Timer.periodic(const Duration(seconds:8),(_){unawaited(_load());});
      }
    }
    unawaited(_load());
  }

  @override
  void dispose(){
    _inboxPoller?.cancel();
    _inboxAuth?.cancel();
    final channel=_inboxChannel;
    if(channel!=null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  Future<void> _load() async {
    if (!AlAniSupportFeature.enabled) {
      setState(() {
        loading = false;
        error = 'محادثات العملاء غير مفعّلة على الإنتاج.';
      });
      return;
    }
    if(!mounted || _loadingNow || _inboxActor==null ||
       Supabase.instance.client.auth.currentUser?.id!=_inboxActor) return;
    if(WidgetsBinding.instance.lifecycleState!=AppLifecycleState.resumed && !loading) return;
    _loadingNow=true;
    try {
      final rows = await Supabase.instance.client
          .from('alani_support_threads')
          .select('id,updated_at')
          .eq('store_id', AlAniSupportFeature.storeId)
          .order('updated_at', ascending: false)
          .limit(60);
      // Only the RLS-checked RPC returns unread counts; no customer
      // profiles, phone numbers or private message bodies enter this inbox.
      final rawCounts = await Supabase.instance.client
          .rpc('alani_support_unread_counts');
      final counts = <String, int>{};
      for (final item in (rawCounts as List<dynamic>)) {
        final count = Map<String, dynamic>.from(item as Map);
        counts[count['thread_id'].toString()] =
            (count['unread_count'] as num?)?.toInt() ?? 0;
      }
      if (mounted && Supabase.instance.client.auth.currentUser?.id==_inboxActor) setState(() {
        threads = rows.map((x) {
          final thread = Map<String, dynamic>.from(x);
          thread['unread_count'] = counts[thread['id'].toString()] ?? 0;
          return thread;
        }).toList();
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted) setState(() {
        loading = false;
        threads=[];
        error = 'تعذّر تحميل محادثات متجرك؛ تأكد من صلاحيات الحساب.';
      });
    } finally {_loadingNow=false;}
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if ((thread['unread_count'] as num? ?? 0) > 0)
                                  Badge(
                                    label: Text(
                                      (thread['unread_count'] as num).toInt()
                                          .clamp(0, 99).toString()),
                                    child: const Icon(Icons.mark_chat_unread),
                                  ),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_left),
                              ],
                            ),
                            onTap: () async {
                              await Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => Scaffold(
                                    appBar: AppBar(title: const Text(
                                        'محادثة خاصة')),
                                    body: AlAniConversation(
                                      threadId: thread['id'].toString(),
                                    ),
                                  ),
                                ),
                              );
                              if (mounted) await _load();
                            },
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
  String? _lastAcknowledgedMessageId;
  String? _actor;
  bool _refreshing=false, _sharePresence=false, _sessionChanged=false;
  DateTime? _lastTyping;
  Map<String,dynamic> _peer={};
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _auth;
  bool get _sameActor => !_sessionChanged && _actor!=null &&
      Supabase.instance.client.auth.currentUser?.id==_actor;
  bool get _foreground => WidgetsBinding.instance.lifecycleState==AppLifecycleState.resumed &&
      ModalRoute.of(context)?.isCurrent!=false;

  @override
  void initState() {
    super.initState();
    if(!AlAniSupportFeature.enabled)return;
    final db=Supabase.instance.client;
    _actor=db.auth.currentUser?.id;
    _auth=db.auth.onAuthStateChange.listen((_){
      if(mounted && db.auth.currentUser?.id!=_actor){
        controller.clear();
        setState((){_sessionChanged=true; messages=[]; _peer={}; _sharePresence=false;});
      }
    });
    if(AlAniSupportFeature.liveTest && _actor!=null){
      _channel=db.channel('support-thread-${widget.threadId}-${identityHashCode(this)}')
        .onPostgresChanges(event:PostgresChangeEvent.insert,schema:'public',table:'alani_support_messages',
          filter:PostgresChangeFilter(type:PostgresChangeFilterType.eq,column:'thread_id',value:widget.threadId),
          callback:(_){if(mounted)unawaited(_refresh());})
        .subscribe();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)unawaited(_refresh());});
    poller = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    poller?.cancel();
    _auth?.cancel();
    final channel=_channel;
    if(channel!=null) Supabase.instance.client.removeChannel(channel);
    scroller.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!AlAniSupportFeature.enabled || !mounted || !_sameActor || _refreshing || !_foreground) return;
    _refreshing=true;
    try {
      final rows = await Supabase.instance.client
          .from('alani_support_messages')
          .select('id,sender_id,body,created_at')
          .eq('thread_id', widget.threadId)
          // Newest 100 records first, then display in chronological order.
          // The old ascending query silently hid all recent messages once
          // a conversation passed 100 messages.
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted || !_sameActor) return;
      final lastMessageId = messages.isEmpty
          ? null : messages.last['id']?.toString();
      final chronological = rows.reversed
          .map((x) => Map<String, dynamic>.from(x)).toList();
      final newestId = chronological.isEmpty
          ? null : chronological.last['id']?.toString();
      setState(() {
        messages = chronological;
        error = null;
      });
      if (newestId != lastMessageId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroller.hasClients) {
            scroller.jumpTo(scroller.position.maxScrollExtent);
          }
        });
      }
      // Acknowledge the last message actually loaded, never 'now'.
      // Do not mark messages read while this route is covered or the
      // application is backgrounded.
      if (newestId != null &&
          newestId != _lastAcknowledgedMessageId &&
          ModalRoute.of(context)?.isCurrent != false &&
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) {
        try {
          await Supabase.instance.client.rpc(
            'alani_mark_support_read',
            params: {
              'p_thread_id': widget.threadId,
              'p_last_seen_message_id': newestId,
            },
          );
          if(mounted && _sameActor) _lastAcknowledgedMessageId = newestId;
        } catch (_) {
          // Display messages even if the acknowledgement is temporarily
          // unavailable. The next refresh will try again.
        }
      }
      if (AlAniSupportFeature.liveTest && mounted && _sameActor && _foreground) {
        try {
          final typing=_lastTyping!=null && DateTime.now().difference(_lastTyping!).inSeconds<6 && controller.text.trim().isNotEmpty;
          if(_sharePresence) await Supabase.instance.client.rpc('alani_support_presence_ping_test',params:{'p_thread_id':widget.threadId,'p_typing':typing});
          if(!mounted || !_sameActor)return;
          final data=await Supabase.instance.client.rpc('alani_support_presence_read_test',params:{'p_thread_id':widget.threadId});
          if(mounted && _sameActor) setState(()=>_peer=Map<String,dynamic>.from(data as Map));
        }catch(_){if(mounted)setState(()=>_peer={});}
      }
    } catch (_) {
      if (mounted) setState(() {
        messages=[]; _peer={};
        error = 'تعذّر تحديث الرسائل. تأكد من الاتصال والصلاحيات.';
      });
    } finally {_refreshing=false;}
  }

  Future<void> _send() async {
    final body = controller.text.trim();
    if (!AlAniSupportFeature.enabled ||
        !_sameActor || !_foreground || submitting || body.isEmpty || body.length > 1500) return;
    setState(() => submitting = true);
    try {
      await Supabase.instance.client.rpc('alani_send_support_message',
        params: {'p_thread_id': widget.threadId, 'p_body': body});
      if (!mounted || !_sameActor) return;
      controller.clear();
      _lastTyping=null;
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
    if(!AlAniSupportFeature.enabled || !_sameActor) return const Center(child:Text('الجلسة غير متاحة. أعد فتح المحادثة.'));
    final me = _actor;
    final seen=DateTime.tryParse(_peer['last_seen_at']?.toString()??'')?.toLocal();
    final peerRead=DateTime.tryParse(_peer['peer_read_at']?.toString()??'');
    return Column(children: [
      const Padding(
        padding: EdgeInsets.all(10),
        child: Text('مراسلة خاصة مع فريق المتجر؛ الإشعارات خارج التطبيق قيد التجهيز.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
      ),
      if (AlAniSupportFeature.liveTest) ...[
        ListTile(dense:true,leading:Icon(_peer['online']==true?Icons.circle:Icons.circle_outlined,color:_peer['online']==true?Colors.green:null),
          title:Text(_peer['typing']==true?'الطرف الآخر يكتب الآن…':_peer['online']==true?'نشط في المحادثة الآن':seen==null?'حالة الاتصال غير معروفة':'آخر نشاط في المحادثة: ${seen.toString().substring(0,16)}')),
        SwitchListTile(dense:true,title:const Text('مشاركة نشاطي داخل هذه المحادثة'),
          subtitle:const Text('اختياري؛ آخر نشاط يبقى مرئياً حتى 7 أيام، وتتوقف حالة النشاط خلال 45 ثانية من التوقف.'),
          value:_sharePresence,onChanged:(v){setState(()=>_sharePresence=v);unawaited(_refresh());}),
      ],
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
                      child: Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
                        Text(msg['body']?.toString() ?? '',textDirection:TextDirection.rtl),
                        if(mine && peerRead!=null && (DateTime.tryParse(msg['created_at']?.toString()??'')?.isAfter(peerRead)==false))
                          const Text('تمت القراءة',style:TextStyle(fontSize:10)),
                      ]),
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
            onChanged:(_){_lastTyping=DateTime.now();},
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
