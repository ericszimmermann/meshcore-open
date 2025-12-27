import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_fork/media_kit_fork.dart';

import '../models/message.dart';

class VoiceMessageBubble extends StatefulWidget {
  final Message message;
  final Color backgroundColor;
  final Color textColor;
  final Color metaColor;
  final bool isOutgoing;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.backgroundColor,
    required this.textColor,
    required this.metaColor,
    required this.isOutgoing,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  late final Player _player;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _completeSubscription;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = Player();
    final voicePath = widget.message.voicePath;
    if (voicePath != null && voicePath.isNotEmpty) {
      _player.open(Media(Uri.file(voicePath).toString()), play: false);
    }
    _durationSubscription = _player.stream.duration.listen((value) {
      if (!mounted) return;
      if (value > Duration.zero && value != _duration) {
        setState(() {
          _duration = value;
        });
      }
    });
    _completeSubscription = _player.stream.completed.listen((completed) {
      if (!completed) return;
      _player.seek(Duration.zero);
      _player.pause();
    });
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _completeSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = widget.message.voicePath != null && widget.message.voicePath!.isNotEmpty;
    final fallbackDuration = Duration(milliseconds: widget.message.voiceDurationMs ?? 0);
    final displayDuration = _duration > Duration.zero ? _duration : fallbackDuration;

    return StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: false,
      builder: (context, playingSnapshot) {
        final isPlaying = playingSnapshot.data ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  color: widget.textColor,
                  onPressed: hasAudio
                      ? () {
                          if (isPlaying) {
                            _player.pause();
                          } else {
                            _player.play();
                          }
                        }
                      : null,
                ),
                Expanded(
                  child: StreamBuilder<Duration>(
                    stream: _player.stream.position,
                    initialData: Duration.zero,
                    builder: (context, positionSnapshot) {
                      final position = positionSnapshot.data ?? Duration.zero;
                      final progress = displayDuration.inMilliseconds > 0
                          ? position.inMilliseconds / displayDuration.inMilliseconds
                          : 0.0;
                      return LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        backgroundColor: widget.metaColor.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(widget.textColor),
                        minHeight: 4,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(displayDuration),
                  style: TextStyle(
                    color: widget.metaColor,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
