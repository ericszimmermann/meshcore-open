import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:record/record.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/utf8_length_limiter.dart';
import '../models/channel_message.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../services/voice_message_service.dart';
import '../services/path_history_service.dart';
import 'channel_message_path_screen.dart';
import 'map_screen.dart';
import '../utils/emoji_utils.dart';
import '../widgets/gif_message.dart';
import '../widgets/gif_picker.dart';
import '../widgets/voice_message.dart';

class ChatScreen extends StatefulWidget {
  final Contact contact;

  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _forceFlood = false;
  final AudioRecorder _voiceRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _voiceStreamSubscription;
  BytesBuilder _voiceBuffer = BytesBuilder(copy: false);
  Timer? _voiceRecordTimer;
  bool _isRecordingVoice = false;
  Message? _pendingVoiceMessage;
  Uint8List? _pendingVoiceCodec2Bytes;
  int? _pendingVoiceTimestampSeconds;
  int? _pendingVoiceDurationMs;
  String? _pendingVoicePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MeshCoreConnector>().setActiveContact(widget.contact.publicKeyHex);
    });
  }

  @override
  void dispose() {
    context.read<MeshCoreConnector>().setActiveContact(null);
    _textController.dispose();
    _scrollController.dispose();
    _voiceRecordTimer?.cancel();
    _voiceStreamSubscription?.cancel();
    unawaited(_voiceRecorder.stop());
    _voiceRecorder.dispose();
    unawaited(_clearPendingVoicePreview(deleteFile: true, notify: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer2<PathHistoryService, MeshCoreConnector>(
          builder: (context, pathService, connector, _) {
            final contact = _resolveContact(connector);
            final unreadCount = connector.getUnreadCountForContactKey(widget.contact.publicKeyHex);
            final unreadLabel = 'Unread: $unreadCount';
            final pathLabel = _forceFlood ? 'Flood (forced)' : _currentPathLabel(contact);
            final canShowPathDetails = !_forceFlood && contact.path.isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(contact.name),
                if (canShowPathDetails)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => _showFullPathDialog(context, contact.path),
                    child: Text(
                      '$pathLabel • $unreadLabel',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                    ),
                  )
                else
                  Text(
                    '$pathLabel • $unreadLabel',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                  ),
              ],
            );
          },
        ),
        centerTitle: false,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(_forceFlood ? Icons.waves : Icons.route),
            tooltip: 'Routing mode',
            onSelected: (mode) {
              setState(() {
                _forceFlood = (mode == 'flood');
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'auto',
                child: Row(
                  children: [
                    Icon(Icons.auto_mode, size: 20, color: !_forceFlood ? Theme.of(context).primaryColor : null),
                    const SizedBox(width: 8),
                    Text(
                      'Auto (use saved path)',
                      style: TextStyle(
                        fontWeight: !_forceFlood ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'flood',
                child: Row(
                  children: [
                    Icon(Icons.waves, size: 20, color: _forceFlood ? Theme.of(context).primaryColor : null),
                    const SizedBox(width: 8),
                    Text(
                      'Force Flood Mode',
                      style: TextStyle(
                        fontWeight: _forceFlood ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.timeline),
            tooltip: 'Path management',
            onPressed: () => _showPathHistory(context),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showContactInfo(context),
          ),
        ],
      ),
      body: Consumer<MeshCoreConnector>(
        builder: (context, connector, child) {
          final messages = connector.getMessages(widget.contact);

          return Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessageList(messages),
              ),
              _buildInputBar(connector),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to ${widget.contact.name}',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<Message> messages) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      cacheExtent: 0,
      addAutomaticKeepAlives: false,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return _MessageBubble(
          message: message,
          senderName: widget.contact.name,
          onTap: () => _openMessagePath(message),
          onLongPress: () => _showMessageActions(message),
        );
      },
    );
  }

  Widget _buildInputBar(MeshCoreConnector connector) {
    final maxBytes = maxContactMessageBytes();
    final isVoiceBusy = connector.isVoiceSending;
    final voiceSupported = Platform.isAndroid || Platform.isIOS;
    final hasPendingVoice = _pendingVoiceMessage != null;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (voiceSupported)
              IconButton(
                icon: Icon(_isRecordingVoice ? Icons.stop_circle : Icons.mic),
                onPressed: (isVoiceBusy || hasPendingVoice) ? null : () => _toggleVoiceRecording(connector),
                tooltip: _isRecordingVoice ? 'Stop recording' : 'Record voice',
              ),
            IconButton(
              icon: const Icon(Icons.gif_box),
              onPressed: (_isRecordingVoice || isVoiceBusy || hasPendingVoice)
                  ? null
                  : () => _showGifPicker(context),
              tooltip: 'Send GIF',
            ),
            Expanded(
              child: hasPendingVoice
                  ? _buildVoicePreview(colorScheme)
                  : ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _textController,
                      builder: (context, value, child) {
                        final gifId = _parseGifId(value.text);
                        if (gifId != null) {
                          return Row(
                            children: [
                              Expanded(
                                child: GifMessage(
                                  url: 'https://media.giphy.com/media/$gifId/giphy.gif',
                                  backgroundColor: colorScheme.surfaceContainerHighest,
                                  fallbackTextColor:
                                      colorScheme.onSurface.withValues(alpha: 0.6),
                                  width: 160,
                                  height: 110,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => _textController.clear(),
                              ),
                            ],
                          );
                        }

                        return TextField(
                          controller: _textController,
                          enabled: !_isRecordingVoice && !isVoiceBusy,
                          inputFormatters: [
                            Utf8LengthLimitingTextInputFormatter(maxBytes),
                          ],
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_isRecordingVoice || isVoiceBusy)
                              ? null
                              : (_) => _sendMessage(connector),
                        );
                      },
                    ),
            ),
            const SizedBox(width: 8),
            if (isVoiceBusy)
              IconButton.filled(
                icon: const Icon(Icons.stop_circle),
                onPressed: () => _cancelVoiceSend(connector),
                tooltip: 'Cancel voice send',
              )
            else if (hasPendingVoice) ...[
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _clearPendingVoicePreview(deleteFile: true),
                tooltip: 'Discard voice message',
              ),
              IconButton.filled(
                icon: const Icon(Icons.send),
                onPressed: () => _sendPendingVoice(connector),
                tooltip: 'Send voice message',
              ),
            ]
            else
              IconButton.filled(
                icon: const Icon(Icons.send),
                onPressed: (_isRecordingVoice || isVoiceBusy)
                    ? null
                    : () => _sendMessage(connector),
              ),
          ],
        ),
      ),
    );
  }

  String? _parseGifId(String text) {
    final trimmed = text.trim();
    final match = RegExp(r'^g:([A-Za-z0-9_-]+)$').firstMatch(trimmed);
    return match?.group(1);
  }

  void _showGifPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => GifPicker(
        onGifSelected: (gifId) {
          _textController.text = 'g:$gifId';
        },
      ),
    );
  }

  void _sendMessage(MeshCoreConnector connector) {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final maxBytes = maxContactMessageBytes();
    if (utf8.encode(text).length > maxBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message too long (max $maxBytes bytes).')),
      );
      return;
    }

    connector.sendMessage(
      widget.contact,
      text,
      forceFlood: _forceFlood,
    );
    _textController.clear();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _cancelVoiceSend(MeshCoreConnector connector) {
    connector.cancelVoiceSend();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice send canceled')),
    );
  }

  Future<void> _toggleVoiceRecording(MeshCoreConnector connector) async {
    if (_isRecordingVoice) {
      await _stopVoiceRecording(connector);
    } else {
      await _startVoiceRecording();
    }
  }

  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice) return;
    final hasPermission = await _voiceRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    _voiceBuffer = BytesBuilder(copy: false);
    try {
      final stream = await _voiceRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: VoiceMessageService.sampleRate,
          numChannels: VoiceMessageService.channels,
        ),
      );
      _voiceStreamSubscription = stream.listen((data) {
        _voiceBuffer.add(data);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start recording: $e')),
      );
      return;
    }
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = Timer(
      const Duration(seconds: VoiceMessageService.maxRecordSeconds),
      () => _stopVoiceRecording(context.read<MeshCoreConnector>()),
    );
    setState(() {
      _isRecordingVoice = true;
    });
  }

  Future<void> _stopVoiceRecording(MeshCoreConnector connector) async {
    if (!_isRecordingVoice) return;
    _voiceRecordTimer?.cancel();
    await _voiceRecorder.stop();
    await _voiceStreamSubscription?.cancel();
    _voiceStreamSubscription = null;
    final pcmBytes = _voiceBuffer.takeBytes();
    setState(() {
      _isRecordingVoice = false;
    });
    if (pcmBytes.isEmpty) return;
    await _prepareVoicePreview(connector, pcmBytes);
  }

  Future<void> _prepareVoicePreview(MeshCoreConnector connector, Uint8List pcmBytes) async {
    final voiceService = VoiceMessageService.instance;
    try {
      final codec2Bytes = voiceService.encodePcmToCodec2(pcmBytes);
      if (codec2Bytes.isEmpty) return;
      final timestampSeconds = connector.reserveVoiceTimestampSeconds();
      final durationMs = voiceService.durationMsForCodec2Bytes(codec2Bytes);
      final decodedPcm = voiceService.decodeCodec2ToPcm(codec2Bytes);
      final fileName = voiceService.buildVoiceFileName(
        senderKeyHex: widget.contact.publicKeyHex,
        timestampSeconds: timestampSeconds,
        outgoing: true,
      );
      final voicePath = await voiceService.writeWavFile(
        pcmBytes: decodedPcm,
        fileName: fileName,
      );

      final previewMessage = Message(
        senderKey: widget.contact.publicKey,
        text: 'Voice message',
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampSeconds * 1000),
        isOutgoing: true,
        isCli: false,
        status: MessageStatus.pending,
        isVoice: true,
        voicePath: voicePath,
        voiceDurationMs: durationMs,
        voiceCodec: VoiceMessageService.codecName,
      );

      if (!mounted) return;
      setState(() {
        _pendingVoiceMessage = previewMessage;
        _pendingVoiceCodec2Bytes = codec2Bytes;
        _pendingVoiceTimestampSeconds = timestampSeconds;
        _pendingVoiceDurationMs = durationMs;
        _pendingVoicePath = voicePath;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice message failed: $e')),
      );
    }
  }

  Widget _buildVoicePreview(ColorScheme colorScheme) {
    final message = _pendingVoiceMessage;
    if (message == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: VoiceMessageBubble(
        message: message,
        backgroundColor: colorScheme.surfaceContainerHighest,
        textColor: colorScheme.onSurface,
        metaColor: colorScheme.onSurface.withValues(alpha: 0.7),
        isOutgoing: true,
      ),
    );
  }

  Future<void> _sendPendingVoice(MeshCoreConnector connector) async {
    final codec2Bytes = _pendingVoiceCodec2Bytes;
    final voicePath = _pendingVoicePath;
    final durationMs = _pendingVoiceDurationMs;
    final timestampSeconds = _pendingVoiceTimestampSeconds;

    if (codec2Bytes == null ||
        codec2Bytes.isEmpty ||
        voicePath == null ||
        voicePath.isEmpty ||
        durationMs == null ||
        timestampSeconds == null) {
      return;
    }
    if (!connector.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to a MeshCore device')),
      );
      return;
    }
    if (connector.isVoiceSending) {
      return;
    }

    await connector.sendVoiceMessage(
      contact: widget.contact,
      codec2Bytes: codec2Bytes,
      voicePath: voicePath,
      durationMs: durationMs,
      timestampSeconds: timestampSeconds,
    );
    unawaited(_clearPendingVoicePreview(deleteFile: false));
  }

  Future<void> _clearPendingVoicePreview({required bool deleteFile, bool notify = true}) async {
    final path = _pendingVoicePath;
    if (notify && mounted) {
      setState(() {
        _pendingVoiceMessage = null;
        _pendingVoiceCodec2Bytes = null;
        _pendingVoiceTimestampSeconds = null;
        _pendingVoiceDurationMs = null;
        _pendingVoicePath = null;
      });
    } else {
      _pendingVoiceMessage = null;
      _pendingVoiceCodec2Bytes = null;
      _pendingVoiceTimestampSeconds = null;
      _pendingVoiceDurationMs = null;
      _pendingVoicePath = null;
    }
    if (deleteFile && path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        return;
      }
    }
  }

  void _showPathHistory(BuildContext context) {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => Consumer<PathHistoryService>(
        builder: (context, pathService, _) {
          final paths = pathService.getRecentPaths(widget.contact.publicKeyHex);
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.timeline),
                SizedBox(width: 8),
                Text('Path Management'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (paths.isNotEmpty) ...[
                    const Text(
                      'Recent ACK Paths (tap to use):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    if (paths.length >= 100) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Path history is full. Remove entries to add new ones.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ...paths.map((path) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: path.wasFloodDiscovery ? Colors.blue : Colors.green,
                            child: Text(
                              '${path.hopCount}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          title: Text(
                            '${path.hopCount} ${path.hopCount == 1 ? 'hop' : 'hops'}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${(path.tripTimeMs / 1000).toStringAsFixed(2)}s • ${_formatRelativeTime(path.timestamp)} • ${path.successCount} successes',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                tooltip: 'Remove path',
                                onPressed: () async {
                                  await pathService.removePathRecord(
                                    widget.contact.publicKeyHex,
                                    path.pathBytes,
                                  );
                                },
                              ),
                              path.wasFloodDiscovery
                                  ? const Icon(Icons.waves, size: 16, color: Colors.grey)
                                  : const Icon(Icons.route, size: 16, color: Colors.grey),
                            ],
                          ),
                          onLongPress: () => _showFullPathDialog(context, path.pathBytes),
                          onTap: () async {
                            if (path.pathBytes.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Path details not available yet. Try sending a message to refresh.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }

                            await connector.setContactPath(
                              widget.contact,
                              Uint8List.fromList(path.pathBytes),
                              path.pathBytes.length,
                            );

                            if (!context.mounted) return;
                            setState(() {
                              _forceFlood = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Using ${path.hopCount} ${path.hopCount == 1 ? 'hop' : 'hops'} path'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                            Navigator.pop(context);
                          },
                        ),
                      );
                    }),
                    const Divider(),
                  ] else ...[
                    const Text('No path history yet.\nSend a message to discover paths.'),
                    const Divider(),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Path Actions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    dense: true,
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.purple,
                      child: Icon(Icons.edit_road, size: 16),
                    ),
                    title: const Text('Set Custom Path', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Manually specify routing path', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      _showCustomPathDialog(context);
                    },
                  ),
                  ListTile(
                    dense: true,
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.orange,
                      child: Icon(Icons.clear_all, size: 16),
                    ),
                    title: const Text('Clear Path', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Force rediscovery on next send', style: TextStyle(fontSize: 11)),
                    onTap: () async {
                      await connector.clearContactPath(widget.contact);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Path cleared. Next message will rediscover route.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    dense: true,
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.waves, size: 16),
                    ),
                    title: const Text('Force Flood Mode', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Use routing toggle in app bar', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      setState(() {
                        _forceFlood = true;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Flood mode enabled. Toggle back via routing icon in app bar.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showFullPathDialog(BuildContext context, List<int> pathBytes) {
    if (pathBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Path details not available yet. Try sending a message to refresh.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final formattedPath = pathBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(',');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Full Path'),
        content: SelectableText(formattedPath),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Contact _resolveContact(MeshCoreConnector connector) {
    return connector.contacts.firstWhere(
      (c) => c.publicKeyHex == widget.contact.publicKeyHex,
      orElse: () => widget.contact,
    );
  }

  String _currentPathLabel(Contact contact) {
    if (contact.pathLength < 0) return 'Flood (auto)';
    if (contact.pathLength == 0) return 'Direct';
    if (contact.pathIdList.isNotEmpty) return contact.pathIdList;
    return '${contact.pathLength} hops';
  }

  void _showContactInfo(BuildContext context) {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    connector.ensureContactSmazSettingLoaded(widget.contact.publicKeyHex);

    showDialog(
      context: context,
      builder: (context) => Consumer<MeshCoreConnector>(
        builder: (context, connector, _) {
          final contact = _resolveContact(connector);
          final smazEnabled = connector.isContactSmazEnabled(contact.publicKeyHex);

          return AlertDialog(
            title: Text(contact.name),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Type', contact.typeLabel),
                  _buildInfoRow('Path', contact.pathLabel),
                  if (contact.hasLocation)
                    _buildInfoRow(
                      'Location',
                      '${contact.latitude?.toStringAsFixed(4)}, ${contact.longitude?.toStringAsFixed(4)}',
                    ),
                  _buildInfoRow('Public Key', contact.publicKeyHex.substring(0, 16) + '...'),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('SMAZ compression'),
                    subtitle: const Text('Compress outgoing messages'),
                    value: smazEnabled,
                    onChanged: (value) {
                      connector.setContactSmazEnabled(contact.publicKeyHex, value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showCustomPathDialog(BuildContext context) {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);

    final currentContact = _resolveContact(connector);
    if (currentContact.pathLength > 0 && currentContact.path.isEmpty && connector.isConnected) {
      connector.getContacts();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_road),
            SizedBox(width: 8),
            Text('Set Custom Path'),
          ],
        ),
        content: Consumer<MeshCoreConnector>(
          builder: (context, connector, _) {
            final contact = _resolveContact(connector);
            final pathForInput = contact.pathIdList;
            final currentPathLabel = _currentPathLabel(contact);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Current path',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: connector.isConnected ? connector.getContacts : null,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reload'),
                    ),
                  ],
                ),
                Text(
                  currentPathLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Choose how to set the message path:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.text_fields, size: 16),
                  ),
                  title: const Text('Enter Path Manually', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Type IDs like: A1B2C3D4,FFEEDDCC', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    _showManualPathInput(
                      context,
                      initialPath: pathForInput.isEmpty ? null : pathForInput,
                    );
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.contacts, size: 16),
                  ),
                  title: const Text('Select from Contacts', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Pick repeaters/rooms as hops', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    _showContactPathPicker(context);
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showManualPathInput(BuildContext context, {String? initialPath}) {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final controller = TextEditingController(text: initialPath ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Custom Path'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter node IDs separated by commas.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Example: A1B2C3D4,FFEEDDCC',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Path',
                hintText: 'A1,A2,A3',
                border: OutlineInputBorder(),
                helperText: 'Node identifiers from your mesh network',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                // Parse comma-separated hex strings and convert to bytes
                final pathIds = path.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                final pathBytesList = <int>[];

                for (final id in pathIds) {
                  if (id.length >= 2) {
                    try {
                      pathBytesList.add(int.parse(id.substring(0, 2), radix: 16));
                    } catch (e) {
                      // Skip invalid hex
                    }
                  }
                }

                if (pathBytesList.isNotEmpty) {
                  await connector.setContactPath(
                    widget.contact,
                    Uint8List.fromList(pathBytesList),
                    pathBytesList.length,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Custom path set: $path'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Set Path'),
          ),
        ],
      ),
    );
  }

  void _showContactPathPicker(BuildContext context) {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final selectedContacts = <Contact>[];

    // Filter to only repeaters and room servers
    final validContacts = connector.contacts
        .where((c) => (c.type == 2 || c.type == 3) && c != widget.contact)
        .toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Build Path from Contacts'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (validContacts.isEmpty) ...[
                  const Icon(Icons.info_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No repeaters or room servers found.',
                    style: TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Custom paths require intermediate hops that can relay messages.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ] else if (selectedContacts.isNotEmpty) ...[
                  const Text(
                    'Selected Path:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selectedContacts.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final contact = entry.value;
                      return Chip(
                        avatar: CircleAvatar(
                          child: Text('${idx + 1}'),
                        ),
                        label: Text(contact.name),
                        onDeleted: () {
                          setDialogState(() {
                            selectedContacts.removeAt(idx);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(),
                ] else
                  const Text(
                    'Tap repeaters/rooms to add them to the path:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                const SizedBox(height: 8),
                if (validContacts.isNotEmpty)
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: validContacts.length,
                      itemBuilder: (context, index) {
                        final contact = validContacts[index];
                        final isSelected = selectedContacts.contains(contact);

                        return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isSelected ? Colors.green : (contact.type == 2 ? Colors.blue : Colors.purple),
                          child: Icon(
                            contact.type == 2 ? Icons.router : Icons.meeting_room,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(contact.name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          '${contact.typeLabel} • ${contact.publicKeyHex.substring(0, 8)}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : const Icon(Icons.add_circle_outline),
                        onTap: () {
                          setDialogState(() {
                            if (isSelected) {
                              selectedContacts.remove(contact);
                            } else {
                              selectedContacts.add(contact);
                            }
                          });
                        },
                      );
                    },
                  ),
                  ),
              ],
            ),
          ),
          actions: [
            if (selectedContacts.isNotEmpty)
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    selectedContacts.clear();
                  });
                },
                child: const Text('Clear'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selectedContacts.isEmpty
                  ? null
                  : () async {
                      // Build path bytes from selected contacts (prefix byte of each pub key)
                      final pathBytesList = <int>[];
                      for (final contact in selectedContacts) {
                        if (contact.publicKeyHex.length >= 2) {
                          try {
                            pathBytesList.add(int.parse(contact.publicKeyHex.substring(0, 2), radix: 16));
                          } catch (e) {
                            // Skip invalid hex
                          }
                        }
                      }

                      if (pathBytesList.isNotEmpty) {
                        await connector.setContactPath(
                          widget.contact,
                          Uint8List.fromList(pathBytesList),
                          pathBytesList.length,
                        );

                        final pathIds = selectedContacts
                            .map((c) => c.publicKeyHex.substring(0, 8))
                            .join(',');

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Custom path set: $pathIds'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          Navigator.pop(context);
                        }
                      }
                    },
              child: const Text('Set Path'),
            ),
          ],
        ),
      ),
    );
  }

  void _openMessagePath(Message message) {
    final connector = context.read<MeshCoreConnector>();
    final senderName =
        message.isOutgoing ? (connector.selfName ?? 'Me') : widget.contact.name;
    final pathMessage = ChannelMessage(
      senderKey: null,
      senderName: senderName,
      text: message.text,
      timestamp: message.timestamp,
      isOutgoing: message.isOutgoing,
      status: ChannelMessageStatus.sent,
      repeatCount: 0,
      pathLength: message.pathLength,
      pathBytes: message.pathBytes,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChannelMessagePathScreen(message: pathMessage),
      ),
    );
  }

  void _showMessageActions(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.isVoice)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _copyMessageText(message.text);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _deleteMessage(message);
              },
            ),
            if (message.isOutgoing &&
                message.status == MessageStatus.failed &&
                !message.isVoice)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Retry'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _retryMessage(message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  void _copyMessageText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied')),
    );
  }

  Future<void> _deleteMessage(Message message) async {
    await context.read<MeshCoreConnector>().deleteMessage(message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message deleted')),
    );
  }

  void _retryMessage(Message message) {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    connector.sendMessage(
      widget.contact,
      message.text,
      forceFlood: message.forceFlood,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Retrying message')),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final String senderName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _MessageBubble({
    required this.message,
    required this.senderName,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    final colorScheme = Theme.of(context).colorScheme;
    final gifId = _parseGifId(message.text);
    final poi = _parsePoiMessage(message.text);
    final isFailed = message.status == MessageStatus.failed;
    final attempts = message.retryCount + 1;
    final bubbleColor = isFailed
        ? colorScheme.errorContainer
        : (isOutgoing ? colorScheme.primary : colorScheme.surfaceContainerHighest);
    final textColor = isFailed
        ? colorScheme.onErrorContainer
        : (isOutgoing ? colorScheme.onPrimary : colorScheme.onSurface);
    final metaColor = textColor.withValues(alpha: 0.7);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          mainAxisAlignment: isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOutgoing) ...[
              _buildAvatar(senderName, colorScheme),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isOutgoing) ...[
                      Text(
                        senderName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (message.isVoice)
                      VoiceMessageBubble(
                        message: message,
                        backgroundColor: bubbleColor,
                        textColor: textColor,
                        metaColor: metaColor,
                        isOutgoing: isOutgoing,
                      )
                    else if (poi != null)
                      _buildPoiMessage(context, poi, textColor, metaColor)
                    else if (gifId != null)
                      GifMessage(
                        url: 'https://media.giphy.com/media/$gifId/giphy.gif',
                        backgroundColor: bubbleColor,
                        fallbackTextColor: textColor.withValues(alpha: 0.7),
                      )
                    else
                      Text(
                        message.text,
                        style: TextStyle(
                          color: textColor,
                        ),
                      ),
                    if (isOutgoing) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Attempts: $attempts',
                        style: TextStyle(
                          fontSize: 10,
                          color: metaColor,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _formatTime(message.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: metaColor,
                          ),
                        ),
                        if (isOutgoing) ...[
                          const SizedBox(width: 4),
                          _buildStatusIcon(metaColor),
                        ],
                        if (message.tripTimeMs != null &&
                            message.status == MessageStatus.delivered) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.speed,
                            size: 10,
                            color: isOutgoing ? metaColor : Colors.green[700],
                          ),
                          Text(
                            '${(message.tripTimeMs! / 1000).toStringAsFixed(1)}s',
                            style: TextStyle(
                              fontSize: 9,
                              color: isOutgoing ? metaColor : Colors.green[700],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _parseGifId(String text) {
    final trimmed = text.trim();
    final match = RegExp(r'^g:([A-Za-z0-9_-]+)$').firstMatch(trimmed);
    return match?.group(1);
  }

  _PoiInfo? _parsePoiMessage(String text) {
    final trimmed = text.trim();
    final match = RegExp(r'^m:([\-0-9.]+),([\-0-9.]+)\|([^|]*)\|.*$')
        .firstMatch(trimmed);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1) ?? '');
    final lon = double.tryParse(match.group(2) ?? '');
    if (lat == null || lon == null) return null;
    final label = match.group(3) ?? '';
    return _PoiInfo(lat: lat, lon: lon, label: label);
  }

  Widget _buildPoiMessage(
    BuildContext context,
    _PoiInfo poi,
    Color textColor,
    Color metaColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.location_on_outlined, color: textColor),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MapScreen(
                  highlightPosition: LatLng(poi.lat, poi.lon),
                  highlightLabel: poi.label,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'POI Shared',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (poi.label.isNotEmpty)
                Text(
                  poi.label,
                  style: TextStyle(
                    color: metaColor,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(String senderName, ColorScheme colorScheme) {
    final initial = _getFirstCharacterOrEmoji(senderName);
    final color = _getColorForName(senderName);

    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.2),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  String _getFirstCharacterOrEmoji(String name) {
    if (name.isEmpty) return '?';

    final emoji = firstEmoji(name);
    if (emoji != null) return emoji;

    final runes = name.runes.toList();
    if (runes.isEmpty) return '?';
    return String.fromCharCode(runes[0]).toUpperCase();
  }

  Color _getColorForName(String name) {
    // Generate a consistent color based on the name hash
    final hash = name.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.teal,
      Colors.indigo,
      Colors.cyan,
      Colors.amber,
      Colors.deepOrange,
    ];

    return colors[hash.abs() % colors.length];
  }

  Widget _buildStatusIcon(Color color) {
    IconData icon;
    switch (message.status) {
      case MessageStatus.pending:
        icon = Icons.access_time;
        break;
      case MessageStatus.sent:
        icon = Icons.schedule;
        break;
      case MessageStatus.delivered:
        icon = Icons.check;
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        break;
    }

    return Icon(
      icon,
      size: 12,
      color: color,
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _PoiInfo {
  final double lat;
  final double lon;
  final String label;

  const _PoiInfo({
    required this.lat,
    required this.lon,
    required this.label,
  });
}
