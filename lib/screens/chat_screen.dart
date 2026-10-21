import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/member_nickname_service.dart';

class ChatScreen extends StatefulWidget {
  final List<CircleModel> circles;
  final CircleModel? selectedCircle;
  final Function(CircleModel)? onCircleSelected;

  const ChatScreen({
    super.key,
    required this.circles,
    this.selectedCircle,
    this.onCircleSelected,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SupabaseService _supa = SupabaseService();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  CircleModel? _activeCircle;
  List<CircleMessage> _messages = [];
  bool _isLoading = false;
  RealtimeChannel? _chatChannel;

  @override
  void initState() {
    super.initState();
    _activeCircle = widget.selectedCircle ?? (widget.circles.isNotEmpty ? widget.circles.first : null);
    MemberNicknameService.instance.addListener(_onNicknamesChanged);
    if (_activeCircle != null) {
      _loadChat(_activeCircle!.id);
      _listenToChat(_activeCircle!.id);
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCircle?.id != oldWidget.selectedCircle?.id) {
      if (widget.selectedCircle != null && widget.selectedCircle?.id != _activeCircle?.id) {
        setState(() {
          _activeCircle = widget.selectedCircle;
        });
        _loadChat(_activeCircle!.id);
        _listenToChat(_activeCircle!.id);
      }
    } else if (_activeCircle == null && widget.circles.isNotEmpty) {
      setState(() {
        _activeCircle = widget.circles.first;
      });
      _loadChat(_activeCircle!.id);
      _listenToChat(_activeCircle!.id);
    }
  }

  @override
  void dispose() {
    MemberNicknameService.instance.removeListener(_onNicknamesChanged);
    _chatChannel?.unsubscribe();
    _msgController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _onNicknamesChanged() {
    if (mounted) setState(() {});
  }

  void _listenToChat(String circleId) {
    _chatChannel?.unsubscribe();
    _chatChannel = _supa.subscribeToMessages(circleId, (newMsg) {
      if (mounted) {
        setState(() {
          _messages.add(newMsg);
        });
        _scrollToBottom();
      }
    }, channelSuffix: 'view');
  }

  Future<void> _loadChat(String circleId) async {
    setState(() => _isLoading = true);
    try {
      final msgs = await _supa.getMessages(circleId);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _activeCircle == null) return;
    _msgController.clear();

    try {
      await _supa.sendMessage(_activeCircle!.id, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal kirim pesan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.circles.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Obrolan Lingkaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF1E293B),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'Anda belum bergabung dalam lingkaran.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    final circle = _activeCircle ?? widget.circles.first;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: const Color(0xFF1E293B),
        title: DropdownButtonHideUnderline(
          child: DropdownButton<CircleModel>(
            value: widget.circles.any((c) => c.id == circle.id) ? circle : widget.circles.first,
            isDense: true,
            icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1E3A8A)),
            items: widget.circles.map((c) {
              return DropdownMenuItem<CircleModel>(
                value: c,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined, size: 18, color: Color(0xFF1E3A8A)),
                    const SizedBox(width: 8),
                    Text(
                      c.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (newCircle) {
              if (newCircle != null && newCircle.id != _activeCircle?.id) {
                setState(() => _activeCircle = newCircle);
                widget.onCircleSelected?.call(newCircle);
                _loadChat(newCircle.id);
                _listenToChat(newCircle.id);
              }
            },
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Segarkan Pesan',
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            onPressed: () => _loadChat(circle.id),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // List Pesan
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.forum_outlined, size: 56, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'Belum ada obrolan di "${circle.name}".\nKirim kabar pertama sekarang!',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _chatScrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) {
                            final msg = _messages[i];
                            final isMe = msg.userId == _supa.currentUser?.id;
                            final nickname = MemberNicknameService.instance.getNickname(msg.userId);
                            final fullName = msg.senderProfile?.fullName ?? 'Anggota';
                            final senderName = isMe ? 'Saya' : (nickname ?? fullName);
                            final senderAvatar = msg.senderProfile?.avatarUrl;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!isMe) ...[
                                    CircleAvatar(
                                      radius: 15,
                                      backgroundColor: const Color(0xFFE2E8F0),
                                      backgroundImage: (senderAvatar != null && senderAvatar.isNotEmpty)
                                          ? NetworkImage(senderAvatar)
                                          : null,
                                      child: (senderAvatar == null || senderAvatar.isEmpty)
                                          ? Text(
                                              senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF1E3A8A),
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isMe ? const Color(0xFF1E3A8A) : Colors.white,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                                          bottomRight: Radius.circular(isMe ? 4 : 16),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                        children: [
                                          if (!isMe) ...[
                                            Text(
                                              senderName,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF1E3A8A),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                          ],
                                          Text(
                                            msg.message,
                                            style: TextStyle(
                                              color: isMe ? Colors.white : const Color(0xFF0F172A),
                                              fontSize: 14,
                                              height: 1.3,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat('HH:mm').format(msg.createdAt),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isMe ? Colors.white70 : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Baris Input Pesan
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      decoration: InputDecoration(
                        hintText: 'Ketik pesan di ${circle.name}...',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(0xFF1E3A8A),
                    shape: const CircleBorder(),
                    elevation: 1,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sendMessage,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.send, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
