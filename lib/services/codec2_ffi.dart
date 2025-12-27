import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int _codec2Mode1300 = 4;

class Codec2Ffi {
  Codec2Ffi._(this._lib)
      : _codec2Create = _lib
            .lookupFunction<_codec2_create_c, _codec2_create_d>('codec2_create'),
        _codec2Destroy = _lib
            .lookupFunction<_codec2_destroy_c, _codec2_destroy_d>('codec2_destroy'),
        _codec2Encode = _lib
            .lookupFunction<_codec2_encode_c, _codec2_encode_d>('codec2_encode'),
        _codec2Decode = _lib
            .lookupFunction<_codec2_decode_c, _codec2_decode_d>('codec2_decode'),
        _codec2SamplesPerFrame = _lib.lookupFunction<_codec2_samples_per_frame_c,
            _codec2_samples_per_frame_d>('codec2_samples_per_frame'),
        _codec2BytesPerFrame = _lib.lookupFunction<_codec2_bytes_per_frame_c,
            _codec2_bytes_per_frame_d>('codec2_bytes_per_frame');

  static final Codec2Ffi instance = Codec2Ffi._(_openLibrary());

  final DynamicLibrary _lib;
  final _codec2_create_d _codec2Create;
  final _codec2_destroy_d _codec2Destroy;
  final _codec2_encode_d _codec2Encode;
  final _codec2_decode_d _codec2Decode;
  final _codec2_samples_per_frame_d _codec2SamplesPerFrame;
  final _codec2_bytes_per_frame_d _codec2BytesPerFrame;

  Codec2Session createSession() {
    final handle = _codec2Create(_codec2Mode1300);
    if (handle == nullptr) {
      throw StateError('codec2_create returned null');
    }
    return Codec2Session._(
      handle: handle,
      destroy: _codec2Destroy,
      encode: _codec2Encode,
      decode: _codec2Decode,
      samplesPerFrame: _codec2SamplesPerFrame,
      bytesPerFrame: _codec2BytesPerFrame,
    );
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libcodec2.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Codec2 is only supported on Android and iOS.');
  }
}

class Codec2Session {
  Codec2Session._({
    required this.handle,
    required this.destroy,
    required this.encode,
    required this.decode,
    required this.samplesPerFrame,
    required this.bytesPerFrame,
  });

  final Pointer<Void> handle;
  final _codec2_destroy_d destroy;
  final _codec2_encode_d encode;
  final _codec2_decode_d decode;
  final _codec2_samples_per_frame_d samplesPerFrame;
  final _codec2_bytes_per_frame_d bytesPerFrame;

  int get samplesPerFrameValue => samplesPerFrame(handle);
  int get bytesPerFrameValue => bytesPerFrame(handle);

  Uint8List encodePcmFrame(Int16List pcmFrame) {
    final bytesOut = calloc<Uint8>(bytesPerFrameValue);
    final pcmIn = calloc<Int16>(samplesPerFrameValue);
    try {
      final sampleCount = samplesPerFrameValue;
      final pcmBuffer = pcmIn.asTypedList(sampleCount);
      final copyLen = pcmFrame.length < sampleCount ? pcmFrame.length : sampleCount;
      pcmBuffer.setRange(0, copyLen, pcmFrame);
      if (copyLen < sampleCount) {
        for (var i = copyLen; i < sampleCount; i++) {
          pcmBuffer[i] = 0;
        }
      }
      encode(handle, bytesOut, pcmIn);
      return Uint8List.fromList(bytesOut.asTypedList(bytesPerFrameValue));
    } finally {
      calloc.free(bytesOut);
      calloc.free(pcmIn);
    }
  }

  Int16List decodeCodecFrame(Uint8List codecFrame) {
    final pcmOut = calloc<Int16>(samplesPerFrameValue);
    final bytesIn = calloc<Uint8>(bytesPerFrameValue);
    try {
      final codecBuffer = bytesIn.asTypedList(bytesPerFrameValue);
      codecBuffer.setRange(0, bytesPerFrameValue, codecFrame);
      decode(handle, pcmOut, bytesIn);
      return Int16List.fromList(pcmOut.asTypedList(samplesPerFrameValue));
    } finally {
      calloc.free(bytesIn);
      calloc.free(pcmOut);
    }
  }

  void dispose() {
    destroy(handle);
  }
}

typedef _codec2_create_c = Pointer<Void> Function(Int32 mode);
typedef _codec2_create_d = Pointer<Void> Function(int mode);

typedef _codec2_destroy_c = Void Function(Pointer<Void> codec2State);
typedef _codec2_destroy_d = void Function(Pointer<Void> codec2State);

typedef _codec2_encode_c = Void Function(
  Pointer<Void> codec2State,
  Pointer<Uint8> bytes,
  Pointer<Int16> speechIn,
);
typedef _codec2_encode_d = void Function(
  Pointer<Void> codec2State,
  Pointer<Uint8> bytes,
  Pointer<Int16> speechIn,
);

typedef _codec2_decode_c = Void Function(
  Pointer<Void> codec2State,
  Pointer<Int16> speechOut,
  Pointer<Uint8> bytes,
);
typedef _codec2_decode_d = void Function(
  Pointer<Void> codec2State,
  Pointer<Int16> speechOut,
  Pointer<Uint8> bytes,
);

typedef _codec2_samples_per_frame_c = Int32 Function(Pointer<Void> codec2State);
typedef _codec2_samples_per_frame_d = int Function(Pointer<Void> codec2State);

typedef _codec2_bytes_per_frame_c = Int32 Function(Pointer<Void> codec2State);
typedef _codec2_bytes_per_frame_d = int Function(Pointer<Void> codec2State);
