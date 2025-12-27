import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'codec2_ffi.dart';

class VoiceMessageService {
  static const int sampleRate = 8000;
  static const int channels = 1;
  static const int bitsPerSample = 16;
  static const int maxRecordSeconds = 5;
  static const int chunkRawBytes = 90;
  static const String codecName = 'codec2_1300';
  static const String chunkPrefix = 'V1|';

  static final VoiceMessageService instance = VoiceMessageService._();

  VoiceMessageService._();

  Future<Directory> ensureVoiceDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(docs.path, 'voice'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String buildVoiceFileName({
    required String senderKeyHex,
    required int timestampSeconds,
    bool outgoing = false,
  }) {
    final suffix = outgoing ? 'out' : 'in';
    return 'voice_${senderKeyHex}_${timestampSeconds}_$suffix.wav';
  }

  List<String> buildVoiceChunks(Uint8List codec2Bytes) {
    if (codec2Bytes.isEmpty) return [];
    final chunks = <Uint8List>[];
    for (var offset = 0; offset < codec2Bytes.length; offset += chunkRawBytes) {
      final end = (offset + chunkRawBytes).clamp(0, codec2Bytes.length).toInt();
      chunks.add(Uint8List.fromList(codec2Bytes.sublist(offset, end)));
    }
    final count = chunks.length;
    return List<String>.generate(count, (index) {
      final encoded = _base64UrlEncodeNoPad(chunks[index]);
      return '$chunkPrefix$index/$count|$encoded';
    });
  }

  VoiceChunk? tryParseChunk(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(chunkPrefix)) return null;
    final match = RegExp(r'^V1\|(\d+)/(\d+)\|([A-Za-z0-9_-]+)$').firstMatch(trimmed);
    if (match == null) return null;
    final idx = int.tryParse(match.group(1) ?? '');
    final count = int.tryParse(match.group(2) ?? '');
    final payload = match.group(3);
    if (idx == null || count == null || payload == null) return null;
    if (idx < 0 || count <= 0 || idx >= count) return null;
    try {
      final bytes = _base64UrlDecode(payload);
      return VoiceChunk(index: idx, count: count, bytes: bytes);
    } catch (_) {
      return null;
    }
  }

  Uint8List encodePcmToCodec2(Uint8List pcmBytes) {
    final session = Codec2Ffi.instance.createSession();
    try {
      final samplesPerFrame = session.samplesPerFrameValue;
      final pcmSamples = _toInt16(pcmBytes);
      final frameCount = (pcmSamples.length + samplesPerFrame - 1) ~/ samplesPerFrame;
      final builder = BytesBuilder(copy: false);

      for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        final start = frameIndex * samplesPerFrame;
        final end = (start + samplesPerFrame).clamp(0, pcmSamples.length).toInt();
        final frame = Int16List(samplesPerFrame);
        final copyLen = end - start;
        if (copyLen > 0) {
          frame.setRange(0, copyLen, pcmSamples.sublist(start, end));
        }
        final encoded = session.encodePcmFrame(frame);
        builder.add(encoded);
      }

      return builder.takeBytes();
    } finally {
      session.dispose();
    }
  }

  Uint8List decodeCodec2ToPcm(Uint8List codec2Bytes) {
    final session = Codec2Ffi.instance.createSession();
    try {
      final bytesPerFrame = session.bytesPerFrameValue;
      if (bytesPerFrame <= 0) return Uint8List(0);
      final frameCount = codec2Bytes.length ~/ bytesPerFrame;
      final builder = BytesBuilder(copy: false);

      for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        final start = frameIndex * bytesPerFrame;
        final frameBytes = codec2Bytes.sublist(start, start + bytesPerFrame);
        final decoded = session.decodeCodecFrame(frameBytes);
        builder.add(Uint8List.view(
          decoded.buffer,
          decoded.offsetInBytes,
          decoded.lengthInBytes,
        ));
      }

      return builder.takeBytes();
    } finally {
      session.dispose();
    }
  }

  int durationMsForCodec2Bytes(Uint8List codec2Bytes) {
    final session = Codec2Ffi.instance.createSession();
    try {
      final bytesPerFrame = session.bytesPerFrameValue;
      final samplesPerFrame = session.samplesPerFrameValue;
      if (bytesPerFrame <= 0 || samplesPerFrame <= 0) return 0;
      final frameCount = codec2Bytes.length ~/ bytesPerFrame;
      final frameDurationMs = (samplesPerFrame * 1000 / sampleRate).round();
      return frameCount * frameDurationMs;
    } finally {
      session.dispose();
    }
  }

  Future<String> writeWavFile({
    required Uint8List pcmBytes,
    required String fileName,
  }) async {
    final dir = await ensureVoiceDir();
    final filePath = path.join(dir.path, fileName);
    final wavHeader = _buildWavHeader(
      pcmDataSize: pcmBytes.length,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    );
    final file = File(filePath);
    final builder = BytesBuilder(copy: false);
    builder.add(wavHeader);
    builder.add(pcmBytes);
    await file.writeAsBytes(builder.takeBytes(), flush: true);
    return filePath;
  }

  Uint8List _buildWavHeader({
    required int pcmDataSize,
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final buffer = BytesBuilder(copy: false);
    buffer.add(ascii.encode('RIFF'));
    buffer.add(_le32(36 + pcmDataSize));
    buffer.add(ascii.encode('WAVE'));
    buffer.add(ascii.encode('fmt '));
    buffer.add(_le32(16));
    buffer.add(_le16(1));
    buffer.add(_le16(channels));
    buffer.add(_le32(sampleRate));
    buffer.add(_le32(byteRate));
    buffer.add(_le16(blockAlign));
    buffer.add(_le16(bitsPerSample));
    buffer.add(ascii.encode('data'));
    buffer.add(_le32(pcmDataSize));
    return buffer.takeBytes();
  }

  Uint8List _le16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List _le32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Int16List _toInt16(Uint8List bytes) {
    final evenLength = bytes.lengthInBytes - (bytes.lengthInBytes % 2);
    if (evenLength <= 0) return Int16List(0);
    return Int16List.view(bytes.buffer, bytes.offsetInBytes, evenLength ~/ 2);
  }

  String _base64UrlEncodeNoPad(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Uint8List _base64UrlDecode(String encoded) {
    final paddedLength = (encoded.length + 3) ~/ 4 * 4;
    final padded = encoded.padRight(paddedLength, '=');
    return base64Url.decode(padded);
  }
}

class VoiceChunk {
  final int index;
  final int count;
  final Uint8List bytes;

  VoiceChunk({
    required this.index,
    required this.count,
    required this.bytes,
  });
}
