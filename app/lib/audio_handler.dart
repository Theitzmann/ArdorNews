import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

// Toca o áudio em segundo plano e controla a notificação/tela de bloqueio
class ArdorAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  // Quanto os botões de avançar/voltar pulam (combina com os ícones de 10s)
  static const _skipInterval = Duration(seconds: 10);

  late final StreamSubscription _playbackEventSub;
  late final StreamSubscription _playingSub;
  late final StreamSubscription _durationSub;

  ArdorAudioHandler() {
    // Repassa os eventos do player pro audio_service manter o sistema em sincronia
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

  // Carrega uma nova URL e define o que aparece na notificação
  Future<void> loadUrl(String url, String title, {String emoji = '📰'}) async {
    mediaItem.add(
      MediaItem(
        id: url,
        title: '$emoji $title',
        artist: 'Ardor News',
        artUri: Uri.parse(
          'android.resource://com.ardornews/mipmap/ic_launcher',
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

  // Chamados pelo sistema quando o usuário toca nos controles da notificação
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> seek(Duration position) => player.seek(position);

  // Botões de +10s e -10s na notificação
  @override
  Future<void> fastForward() => player.seek(player.position + _skipInterval);

  @override
  Future<void> rewind() {
    final newPos = player.position - _skipInterval;
    return player.seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  // Mantém a notificação do sistema em sincronia com o estado real do player
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

  // Libera o player quando o app é removido dos recentes
  @override
  Future<void> onTaskRemoved() async {
    await _playbackEventSub.cancel();
    await _playingSub.cancel();
    await _durationSub.cancel();
    await stop();
    await player.dispose();
    await super.onTaskRemoved();
  }
}
