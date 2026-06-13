import 'dart:async'; // For StreamSubscription

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:just_audio/just_audio.dart';

// This class runs in the background and controls the audio player.
// It also tells the OS what to show in the notification and lock screen.
class ArdorAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  // Skip interval used by fastForward() and rewind() — kept at 10s to match
  // the replay_10/forward_10 icons shown in the app and the OS notification
  static const _skipInterval = Duration(seconds: 10);

  // Stored subscriptions so they can be cancelled in onTaskRemoved()
  late final StreamSubscription _playbackEventSub;
  late final StreamSubscription _playingSub;
  late final StreamSubscription _durationSub;

  ArdorAudioHandler() {
    // Forward player events to audio_service so the OS stays in sync
    _playbackEventSub = player.playbackEventStream.listen(_updatePlaybackState);
    _playingSub = player.playingStream.listen(
      (_) => _updatePlaybackState(player.playbackEvent),
    );
    _durationSub = player.durationStream.listen((duration) {
      if (duration == null) return;
      final current = mediaItem.value;
      if (current != null) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
  }

  // Load a new audio URL and set the media info shown in the notification
  Future<void> loadUrl(String url, String title, {String emoji = '📰'}) async {
    mediaItem.add(
      MediaItem(
        id: url,
        title: '$emoji $title',
        artist: 'Ardor News',
        // Uses the app launcher icon as notification artwork
        artUri: Uri.parse(
          'android.resource://com.example.app/mipmap/ic_launcher',
        ),
      ),
    );
    try {
      await player.setUrl(url);
    } catch (e) {
      debugPrint('Erro ao carregar URL de áudio: $e');
      rethrow;
    }
  }

  // These methods are called by the OS when the user taps
  // the notification controls
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> seek(Duration position) => player.seek(position);

  // +10s and -10s buttons in the notification
  @override
  Future<void> fastForward() => player.seek(player.position + _skipInterval);

  @override
  Future<void> rewind() {
    final newPos = player.position - _skipInterval;
    return player.seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  // Keeps the OS notification in sync with the actual player state
  void _updatePlaybackState(PlaybackEvent event) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[player.processingState]!,
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
      ),
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    // Cancel stream subscriptions before disposing the player
    await _playbackEventSub.cancel();
    await _playingSub.cancel();
    await _durationSub.cancel();
    await stop();
    // Release audio resources when the user swipes the app away from recents
    await player.dispose();
    await super.onTaskRemoved();
  }
}
