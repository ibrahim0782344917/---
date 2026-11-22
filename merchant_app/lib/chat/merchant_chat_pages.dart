import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Merchant inbox only shows threads for stores owned by the signed-in user.
class MerchantChatInboxPage extends StatefulWidget {
  const MerchantChatInboxPage({super.key});
  @override
  State<MerchantChatInboxPage> createState() => _MerchantChatInboxPageState();
}

class _MerchantChatInboxPageState extends State<MerchantChatInboxPage> {
  late Future<List<Map<String, dynamic>>> _threads;

  @override
  void initState() {
    super.initState();
    _threads = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('shitreed_chat_threads')
        .select('id,store_id,last_message_at,stores(name)')
        .order('last_message_at', ascending: false)
        .limit(100);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _threads = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('رسائل الزبائن')),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _threads,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(children: const [
              ListTile(title: Text('تعذر جلب المحادثات. تحقق من تفعيل الخدمة.')),
            ]);
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return ListView(children: const [
              ListTile(title: Text('ماكو محادثات من زبائنك حالياً.')),
            ]);
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final item = rows[index];
              final store = item['stores'];
              final storeName = store is Map
                  ? (store['name']?.toString() ?? 'متجر') : 'متجر';
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.chat_bubble_outline)),
                title: Text('محادثة • ' + storeName),
                subtitle: const Text('محادثة خاصة بالزبون والمتجر'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => MerchantChatThreadPage(
                    threadId: item['id'] as String,
                    storeName: storeName,
                  ),
                )),
              );
            },
          );
        },
      ),
    ),
  );
}

class MerchantChatThreadPage extends StatefulWidget {
  final String threadId;
  final String storeName;
  const MerchantChatThreadPage({
    super.key, required this.threadId, required this.storeName,
  });
  @override
  State<MerchantChatThreadPage> createState() => _MerchantChatThreadPageState();
}

class _MerchantChatThreadPageState extends State<MerchantChatThreadPage> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _text.text.trim();
    if (_busy || value.isEmpty || value.length > 2000) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('shitreed_chat_send', params: {
        'p_thread_id': widget.threadId,
        'p_body': value,
      });
      if (mounted) _text.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الرسالة ما انرسلت؛ تحقق من الاتصال وصلاحية المتجر.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    final me = db.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: Text(widget.storeName)),
      body: SafeArea(child: Column(children: [
        Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: db.from('shitreed_chat_messages')
              .stream(primaryKey: ['id'])
              .eq('thread_id', widget.threadId)
              .order('created_at'),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر عرض الرسائل.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return const Center(child: Text('ماكو رسائل بهالمحادثة بعد.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final mine = item['sender_id'] == me;
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 310),
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: mine ? const Color(0xFFE8D5FF) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(item['body']?.toString() ?? ''),
                  ),
                );
              },
            );
          },
        )),
        Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          Expanded(child: TextField(
            controller: _text, minLines: 1, maxLines: 4, maxLength: 2000,
            decoration: const InputDecoration(
              hintText: 'الرد على الزبون',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          )),
          IconButton.filled(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send),
          ),
        ])),
      ])),
    );
  }
}
