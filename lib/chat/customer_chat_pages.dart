import 'package:flutter/material.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/auth/customer_auth_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thread/message access is enforced in the database. No customer phone
/// numbers, orders, or administrative data are requested for chat.
class CustomerChatInboxPage extends StatefulWidget {
  const CustomerChatInboxPage({super.key});
  @override
  State<CustomerChatInboxPage> createState() => _CustomerChatInboxPageState();
}

class _CustomerChatInboxPageState extends State<CustomerChatInboxPage> {
  late Future<List<Map<String, dynamic>>> _threads;

  @override
  void initState() {
    super.initState();
    _threads = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!MarketplaceBackend.configured || MarketplaceBackend.currentUser == null) {
      return [];
    }
    final data = await Supabase.instance.client
        .from('shitreed_chat_threads')
        .select('id,store_id,last_message_at,stores(name)')
        .order('last_message_at', ascending: false)
        .limit(100);
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _threads = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('محادثاتي مع المتاجر')),
        body: MarketplaceBackend.currentUser == null
            ? Center(
                child: FilledButton(
                  onPressed: () async {
                    await Navigator.push<void>(context,
                        MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
                    if (mounted) await _refresh();
                  },
                  child: const Text('سجل الدخول للمحادثات'),
                ),
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _threads,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return ListView(children: const [
                        ListTile(title: Text('تعذر فتح المحادثات. تأكد من تفعيل الخدمة.')),
                      ]);
                    }
                    final threads = snapshot.data ?? [];
                    if (threads.isEmpty) {
                      return ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('ما عندك محادثات بعد. افتح متجراً واختر «راسل المتجر».'),
                        ),
                      ]);
                    }
                    return ListView.builder(
                      itemCount: threads.length,
                      itemBuilder: (context, index) {
                        final thread = threads[index];
                        final store = thread['stores'];
                        final name = store is Map
                            ? (store['name']?.toString() ?? 'متجر')
                            : 'متجر';
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.storefront)),
                          title: Text(name),
                          subtitle: const Text('محادثة خاصة مع المتجر'),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => CustomerChatThreadPage(
                                threadId: thread['id'] as String,
                                title: name,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
      );
}

class CustomerChatThreadPage extends StatefulWidget {
  final String threadId;
  final String title;
  const CustomerChatThreadPage({
    super.key,
    required this.threadId,
    required this.title,
  });
  @override
  State<CustomerChatThreadPage> createState() => _CustomerChatThreadPageState();
}

class _CustomerChatThreadPageState extends State<CustomerChatThreadPage> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (_sending || content.isEmpty || content.length > 2000) return;
    setState(() => _sending = true);
    try {
      await Supabase.instance.client.rpc('shitreed_chat_send', params: {
        'p_thread_id': widget.threadId,
        'p_body': content,
      });
      if (mounted) _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر إرسال الرسالة. حاول مجدداً.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    final myId = db.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: db.from('shitreed_chat_messages')
                  .stream(primaryKey: ['id'])
                  .eq('thread_id', widget.threadId)
                  .order('created_at'),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text(
                    'تعذر عرض الرسائل. تحقق من الاتصال أو صلاحيات المحادثة.',
                  ));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const Center(child: Text('ابدأ المحادثة برسالة محترمة.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final m = items[index];
                    final mine = m['sender_id'] == myId;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 305),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: mine ? const Color(0xFFE8D5FF) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(m['body'] as String? ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'اكتب رسالة للمتجر',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Start a conversation only after login; the server checks store approval
/// and rejects sending messages to your own store.
Future<void> openCustomerStoreChat(
    BuildContext context, String storeId, String storeName) async {
  if (MarketplaceBackend.currentUser == null) {
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CustomerAuthPage()),
    );
    if (!context.mounted || loggedIn != true) return;
  }
  try {
    final id = await Supabase.instance.client.rpc(
      'shitreed_chat_open', params: {'p_store_id': storeId},
    );
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => CustomerChatThreadPage(
        threadId: id as String,
        title: storeName,
      ),
    ));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر بدء المحادثة. تأكد من اتصالك واعتماد المتجر.'),
      ));
    }
  }
}
