import 'package:audioplayers/audioplayers.dart';
import 'package:on_audio_query/on_audio_query.dart';

// A simple local music player for the run screen.
// It can load EVERY song on the phone at once (no picking one by one), then
// play/pause and skip next/previous. When a song ends it auto-plays the next.
class MusicPlayer {
  final AudioPlayer _player = AudioPlayer();
  final OnAudioQuery _query = OnAudioQuery();

  List<SongModel> songs = []; // all songs found on the phone
  int currentIndex = 0;
  bool isPlaying = false;
  bool _started = false; // have we played anything yet?

  // The run screen sets this so it can refresh when the song changes.
  void Function()? onChanged;

  MusicPlayer() {
    // When a song finishes, play the next one.
    _player.onPlayerComplete.listen((_) => next());
  }

  bool get hasSongs => songs.isNotEmpty;
  int get songCount => songs.length;
  String get currentTitle => hasSongs ? songs[currentIndex].title : 'No music';

  // Find ALL songs on the phone in one go. Returns how many were found.
  Future<int> loadAllSongs() async {
    // Ask for the "read audio" permission the first time.
    var granted = await _query.permissionsStatus();
    if (!granted) granted = await _query.permissionsRequest();
    if (!granted) return 0;

    songs = await _query.querySongs();
    currentIndex = 0;
    _started = false;
    onChanged?.call();
    return songs.length;
  }

  Future<void> _playCurrent() async {
    if (!hasSongs) return;
    await _player.play(DeviceFileSource(songs[currentIndex].data));
    isPlaying = true;
    _started = true;
    onChanged?.call();
  }

  // Play / pause. The first tap starts the first song.
  Future<void> togglePlay() async {
    if (!hasSongs) return;
    if (isPlaying) {
      await _player.pause();
      isPlaying = false;
    } else if (_started) {
      await _player.resume();
      isPlaying = true;
    } else {
      await _playCurrent();
    }
    onChanged?.call();
  }

  Future<void> next() async {
    if (!hasSongs) return;
    currentIndex = (currentIndex + 1) % songs.length;
    await _playCurrent();
  }

  Future<void> previous() async {
    if (!hasSongs) return;
    currentIndex = (currentIndex - 1 + songs.length) % songs.length;
    await _playCurrent();
  }

  void dispose() {
    _player.dispose();
  }
}
