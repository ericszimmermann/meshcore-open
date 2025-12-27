import 'dart:typed_data';
import '../connector/meshcore_protocol.dart';

enum MessageStatus { pending, sent, delivered, failed }

class Message {
  final Uint8List senderKey;
  final String text;
  final DateTime timestamp;
  final bool isOutgoing;
  final bool isCli;
  final MessageStatus status;
  final bool isVoice;
  final String? voicePath;
  final int? voiceDurationMs;
  final String? voiceCodec;

  // NEW: Retry logic fields
  final String? messageId;
  final int retryCount;
  final int? estimatedTimeoutMs;
  final Uint8List? expectedAckHash;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final int? tripTimeMs;
  final bool forceFlood;
  final int? pathLength;
  final Uint8List pathBytes;

  Message({
    required this.senderKey,
    required this.text,
    required this.timestamp,
    required this.isOutgoing,
    this.isCli = false,
    this.status = MessageStatus.pending,
    this.isVoice = false,
    this.voicePath,
    this.voiceDurationMs,
    this.voiceCodec,
    this.messageId,
    this.retryCount = 0,
    this.estimatedTimeoutMs,
    this.expectedAckHash,
    this.sentAt,
    this.deliveredAt,
    this.tripTimeMs,
    this.forceFlood = false,
    this.pathLength,
    Uint8List? pathBytes,
  }) : pathBytes = pathBytes ?? Uint8List(0);

  String get senderKeyHex => pubKeyToHex(senderKey);

  Message copyWith({
    MessageStatus? status,
    int? retryCount,
    int? estimatedTimeoutMs,
    Uint8List? expectedAckHash,
    DateTime? sentAt,
    DateTime? deliveredAt,
    int? tripTimeMs,
    int? pathLength,
    Uint8List? pathBytes,
    bool? isCli,
    bool? isVoice,
    String? voicePath,
    int? voiceDurationMs,
    String? voiceCodec,
  }) {
    return Message(
      senderKey: senderKey,
      text: text,
      timestamp: timestamp,
      isOutgoing: isOutgoing,
      isCli: isCli ?? this.isCli,
      status: status ?? this.status,
      isVoice: isVoice ?? this.isVoice,
      voicePath: voicePath ?? this.voicePath,
      voiceDurationMs: voiceDurationMs ?? this.voiceDurationMs,
      voiceCodec: voiceCodec ?? this.voiceCodec,
      messageId: messageId,
      retryCount: retryCount ?? this.retryCount,
      estimatedTimeoutMs: estimatedTimeoutMs ?? this.estimatedTimeoutMs,
      expectedAckHash: expectedAckHash ?? this.expectedAckHash,
      sentAt: sentAt ?? this.sentAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      tripTimeMs: tripTimeMs ?? this.tripTimeMs,
      forceFlood: forceFlood,
      pathLength: pathLength ?? this.pathLength,
      pathBytes: pathBytes ?? this.pathBytes,
    );
  }

  static Message? fromFrame(Uint8List data, Uint8List selfPubKey) {
    if (data.length < msgTextOffset + 1) return null;

    final code = data[0];
    if (code != respCodeContactMsgRecv && code != respCodeContactMsgRecvV3) {
      return null;
    }

    final senderKey = Uint8List.fromList(
      data.sublist(msgPubKeyOffset, msgPubKeyOffset + pubKeySize),
    );
    final timestampRaw = readUint32LE(data, msgTimestampOffset);
    final flags = data[msgFlagsOffset];
    if ((flags >> 2) != txtTypePlain) {
      return null;
    }
    final text = readCString(data, msgTextOffset, data.length - msgTextOffset);

    return Message(
      senderKey: senderKey,
      text: text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampRaw * 1000),
      isOutgoing: false,
      isCli: false,
      status: MessageStatus.delivered,
      isVoice: false,
      pathBytes: Uint8List(0),
    );
  }

  static Message outgoing(
    Uint8List recipientKey,
    String text, {
    int? pathLength,
    Uint8List? pathBytes,
  }) {
    return Message(
      senderKey: recipientKey,
      text: text,
      timestamp: DateTime.now(),
      isOutgoing: true,
      isCli: false,
      status: MessageStatus.pending,
      isVoice: false,
      pathLength: pathLength,
      pathBytes: pathBytes,
    );
  }
}
