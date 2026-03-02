import 'dart:async';

import 'package:flserial/flserial.dart';
import 'package:flserial/flserial_exception.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Wraps the native flserial plugin to expose a stream of raw bytes for the
/// MeshCore connector to consume.
class UsbSerialService {
  UsbSerialService();

  static const MethodChannel _androidMethodChannel = MethodChannel(
    'meshcore_open/android_usb_serial',
  );
  static const EventChannel _androidEventChannel = EventChannel(
    'meshcore_open/android_usb_serial_events',
  );
  static const int _serialTxFrameStart = 0x3c;
  static const int _serialRxFrameStart = 0x3e;
  static const int _serialHeaderLength = 3;

  final StreamController<Uint8List> _frameController =
      StreamController<Uint8List>.broadcast();
  final FlSerial _serial = FlSerial();
  final List<int> _rxBuffer = <int>[];
  StreamSubscription<dynamic>? _androidDataSubscription;
  StreamSubscription<FlSerialEventArgs>? _dataSubscription;
  UsbSerialStatus _status = UsbSerialStatus.disconnected;
  String? _connectedPortName;

  UsbSerialStatus get status => _status;
  String? get activePortName => _connectedPortName;
  Stream<Uint8List> get frameStream => _frameController.stream;
  bool get _useAndroidUsbHost =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isConnected {
    if (_useAndroidUsbHost) {
      return _status == UsbSerialStatus.connected;
    }
    return _status == UsbSerialStatus.connected &&
        _serial.isOpen() == FlOpenStatus.open;
  }

  Future<List<String>> listPorts() async {
    if (_useAndroidUsbHost) {
      final ports = await _androidMethodChannel.invokeListMethod<String>(
        'listPorts',
      );
      return ports ?? <String>[];
    }
    return Future.value(FlSerial.listPorts());
  }

  Future<void> connect({
    required String portName,
    int baudRate = 115200,
  }) async {
    if (_status == UsbSerialStatus.connected ||
        _status == UsbSerialStatus.connecting) {
      throw StateError('USB serial transport is already active');
    }

    _status = UsbSerialStatus.connecting;
    final normalizedPortName = _normalizePortName(portName);

    if (_useAndroidUsbHost) {
      try {
        await _androidMethodChannel.invokeMethod<void>('connect', {
          'portName': normalizedPortName,
          'baudRate': baudRate,
        });
        debugPrint(
          'USB serial opened port=$normalizedPortName on Android via USB host bridge',
        );
      } on PlatformException catch (error) {
        _status = UsbSerialStatus.disconnected;
        throw StateError(error.message ?? error.code);
      }
    } else {
      _serial.init();

      try {
        final status = _serial.openPort(normalizedPortName, baudRate);
        if (status != FlOpenStatus.open) {
          throw StateError(
            'Failed to open USB port $normalizedPortName ($status)',
          );
        }
        _serial.setByteSize8();
        _serial.setBitParityNone();
        _serial.setStopBits1();
        _serial.setFlowControlNone();
        _serial.setRTS(false);
        _serial.setDTR(true);
        debugPrint(
          'USB serial opened port=$normalizedPortName cts=${_serial.getCTS()} dsr=${_serial.getDSR()} dtr=true rts=false',
        );
      } on FlSerialException catch (error) {
        _serial.free();
        _status = UsbSerialStatus.disconnected;
        throw StateError(
          'Failed to open USB port $normalizedPortName: ${error.msg} (${error.error})',
        );
      } catch (error) {
        _serial.free();
        _status = UsbSerialStatus.disconnected;
        rethrow;
      }
    }

    _connectedPortName = normalizedPortName;
    if (_useAndroidUsbHost) {
      _androidDataSubscription = _androidEventChannel
          .receiveBroadcastStream()
          .listen(
            _handleAndroidData,
            onError: _handleSerialError,
            onDone: _handleSerialDone,
          );
    } else {
      _dataSubscription = _serial.onSerialData.stream.listen(
        _handleSerialData,
        onError: _handleSerialError,
        onDone: _handleSerialDone,
      );
    }
    _status = UsbSerialStatus.connected;
  }

  Future<void> write(Uint8List data) async {
    if (!isConnected) {
      throw StateError('USB serial port is not open');
    }
    final packet = Uint8List(_serialHeaderLength + data.length);
    packet[0] = _serialTxFrameStart;
    packet[1] = data.length & 0xff;
    packet[2] = (data.length >> 8) & 0xff;
    packet.setRange(_serialHeaderLength, packet.length, data);
    _logFrameSummary('USB TX frame', data);
    if (_useAndroidUsbHost) {
      try {
        await _androidMethodChannel.invokeMethod<void>('write', {
          'data': packet,
        });
      } on PlatformException catch (error) {
        throw StateError(error.message ?? error.code);
      }
    } else {
      _serial.write(packet);
    }
  }

  Future<void> disconnect() async {
    if (_status == UsbSerialStatus.disconnected) return;

    _status = UsbSerialStatus.disconnecting;
    _connectedPortName = null;
    await _androidDataSubscription?.cancel();
    _androidDataSubscription = null;
    await _dataSubscription?.cancel();
    _dataSubscription = null;

    if (_useAndroidUsbHost) {
      try {
        await _androidMethodChannel.invokeMethod<void>('disconnect');
      } catch (_) {
        // Ignore errors while closing.
      }
    } else {
      try {
        if (_serial.isOpen() == FlOpenStatus.open) {
          _serial.closePort();
        }
      } catch (_) {
        // Ignore errors while closing.
      }

      _serial.free();
    }
    _status = UsbSerialStatus.disconnected;
  }

  void dispose() {
    unawaited(disconnect());
    unawaited(_frameController.close());
  }

  void _handleSerialData(FlSerialEventArgs event) {
    try {
      final bytes = event.serial.readList();
      if (bytes.isNotEmpty) {
        _ingestRawBytes(Uint8List.fromList(bytes));
      }
    } catch (error, stack) {
      _frameController.addError(error, stack);
    }
  }

  void _handleAndroidData(dynamic data) {
    if (data is Uint8List) {
      _ingestRawBytes(data);
      return;
    }
    if (data is ByteData) {
      _ingestRawBytes(data.buffer.asUint8List());
      return;
    }
    _frameController.addError(
      StateError('Unexpected Android USB event payload: ${data.runtimeType}'),
    );
  }

  void _handleSerialError(Object error, [StackTrace? stackTrace]) {
    _frameController.addError(error, stackTrace);
  }

  void _handleSerialDone() {
    unawaited(disconnect());
  }

  String _normalizePortName(String portName) {
    final separatorIndex = portName.indexOf(' - ');
    final normalized = separatorIndex >= 0
        ? portName.substring(0, separatorIndex)
        : portName;
    return normalized.trim();
  }

  void _ingestRawBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return;
    }
    _rxBuffer.addAll(bytes);
    _drainRxBuffer();
  }

  void _drainRxBuffer() {
    while (true) {
      if (_rxBuffer.isEmpty) {
        return;
      }

      if (_rxBuffer.first != _serialRxFrameStart &&
          _rxBuffer.first != _serialTxFrameStart) {
        _rxBuffer.removeAt(0);
        continue;
      }

      if (_rxBuffer.length < _serialHeaderLength) {
        return;
      }

      final payloadLength = _rxBuffer[1] | (_rxBuffer[2] << 8);
      final packetLength = _serialHeaderLength + payloadLength;
      if (_rxBuffer.length < packetLength) {
        return;
      }

      final frameStart = _rxBuffer.first;
      final payload = Uint8List.fromList(
        _rxBuffer.sublist(_serialHeaderLength, packetLength),
      );
      _rxBuffer.removeRange(0, packetLength);
      if (frameStart != _serialRxFrameStart) {
        debugPrint(
          'USB ignored packet start=0x${frameStart.toRadixString(16).padLeft(2, '0')} len=${payload.length}',
        );
      }
      _frameController.add(payload);
    }
  }

  void _logFrameSummary(String prefix, Uint8List bytes) {
    if (bytes.isEmpty) {
      debugPrint('$prefix len=0');
      return;
    }
    debugPrint('$prefix code=${bytes[0]} len=${bytes.length}');
  }
}

enum UsbSerialStatus { disconnected, connecting, connected, disconnecting }
