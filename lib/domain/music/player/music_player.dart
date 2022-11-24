import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ntp/ntp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sound_share/common/logger.dart';
import 'package:sound_share/common/utils/disposable.dart';
import 'package:sound_share/domain/music/buffer/music_buffer_controller.dart';
import 'package:sound_share/domain/music/package/details_package.dart';
import 'package:sound_share/domain/music/package/music_package.dart';
import 'package:sound_share/domain/music/player/bytes_audio_source.dart';
import 'package:sound_share/domain/music/player/music_queue.dart';
import 'package:sound_share/domain/music/synchronization/synchronization.dart';
import 'package:sound_share/domain/network/p2p/p2p_network.dart';

/// Plays the music from the received packages
class MusicPlayer with Disposable implements MusicPlayerListener {
  final _player = AudioPlayer();
  final MusicBufferController _musicBuffer;
  final MusicQueue _musicQueue;
  late final Duration _playOffset;
  AudioSession? _session;
  var _source = BytesAudioSource(null);
  var _timeOffset = const Duration();
  Timer? _timer;

  Stream<PlayerState> get playerState => _player.playerStateStream;

  MusicPlayer(this._musicBuffer, this._musicQueue) {
    _player.processingStateStream.listen((event) {
      if (event == ProcessingState.completed) {
        final song = _musicQueue.nextSong();
        _playSong(song, Duration(seconds: 2) - _playOffset);
      }
    }).canceledBy(this);
    AudioSession.instance.then((value) {
      _session = value;
      _session!.configure(const AudioSessionConfiguration.music());
    });
    SharedPreferences.getInstance().then((value) =>
        _playOffset = Duration(milliseconds: value.getInt('playOffset') ?? 0));
  }

  Future<void> _setSong(BytesAudioSource source) async {
    _source = source;
    pause();
    try {
      await _player.setAudioSource(source);
    } on PlayerInterruptedException catch (_) {
      logger.w("setAudioSource interrupted");
    }
    _player.play();
  }

  void addPackage(MusicPackage package) {
    logger.d("#### Add song package ${package.data.length}");
    _source.addData(package.startIndex, package.data.toList());
  }

  void play(DateTime time) async {
    if (await _session!.setActive(true)) {
      _timer?.cancel();
      _timer = Timer(
          DateTime.now().add(_timeOffset).difference(time) +
              const Duration(seconds: 2), () {
        _player.play();
      });
    } else {
      print("Session did not activate.");
      return;
    }
  }

  Future<void> _playSong(DetailsPackage song, Duration? songPosition) async {
    logger.d("#### Set new song ${song.bytesLength}");
    final source = _musicBuffer.getSong(song);
    await _setSong(source);
    _player.seek(songPosition);
  }

  Duration? getCurrentSongDuration() {
    return _player.duration;
  }

  Duration? getCurrentSongPosition() {
    return _player.position;
  }

  Duration? time = const Duration();

  void pause() {
    time = _player.position;
    _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  @override
  void addToQueue(DetailsPackage song) {
    _musicQueue.addSong(song);
  }

  @override
  List<DetailsPackage> getQueue() {
    return _musicQueue.songList;
  }

  @override
  void onPause() {
    pause();
  }

  @override
  void onPlay(int index, DateTime time, {Duration? songPosition}) {
    _musicQueue.setIndex(index);
    final song = _musicQueue.currentSong;
    if (song == null) {
      logger.e("onPlay song index '$index' is null");
      return;
    }
    _playSong(song, songPosition);
    // _timer?.cancel();
    // _timer = Timer(
    //     DateTime.now().difference(time) + _offset + const Duration(seconds: 10),
    //     () {
    //   _playSong(song);
    // });
  }

  @override
  void removeFromQueue(int index) {
    // TODO: implement removeFromQueue
  }

  @override
  void updateQueue(List<DetailsPackage> songs) {
    if (_musicQueue.songList.isEmpty) {
      for (var song in songs) {
        _musicQueue.addSong(song);
      }
    }
  }

  @override
  void onSync() {
    NTP
        .getNtpOffset(
          localTime: DateTime.now(),
          lookUpAddress: 'time.facebook.com',
        )
        .then((timeOffset) =>
            _timeOffset = Duration(milliseconds: timeOffset) - _playOffset);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
