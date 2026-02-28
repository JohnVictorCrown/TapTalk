import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const TapTalkApp());
}

class TapTalkApp extends StatelessWidget {
  const TapTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TapTalk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00BFA6),
          surface: Color(0xFF1E1E2C),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2D2D44),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Colors.grey),
          counterStyle: const TextStyle(color: Colors.grey),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// GRADIENT BACKGROUND
// ---------------------------------------------------------------------------
class GradientBackground extends StatelessWidget {
  final Widget child;
  const GradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1A2E), // Dark Navy
            Color(0xFF16213E), // Deep Blue
            Color(0xFF240046), // Deep Purple
          ],
        ),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// HOME SCREEN
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterTts flutterTts = FlutterTts();
  final TextEditingController _textController = TextEditingController();
  
  // State variables
  List<String> phrases = [];
  bool _isLoopMode = false; // Controls if we repeat
  bool _isPlaying = false;  // Controls the Stop button visibility
  String? _currentPhrase;   // Tracks what is currently playing

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // Helper to fix the crash with Map types
  Map<String, String> _safeVoiceMap(Map<dynamic, dynamic> voice) {
    final Map<String, String> safeMap = {};
    voice.forEach((key, value) {
      safeMap[key.toString()] = value.toString();
    });
    return safeMap;
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Load Phrases (Cache)
    List<String>? savedPhrases = prefs.getStringList('saved_phrases');
    if (savedPhrases != null) {
      setState(() => phrases = savedPhrases);
    }

    // 2. Load Voice Settings
    try {
      double pitch = prefs.getDouble('pitch') ?? 1.0;
      double rate = prefs.getDouble('rate') ?? 0.5;
      String? language = prefs.getString('language') ?? "en-US";
      String? voiceJson = prefs.getString('voice');

      // CRITICAL FOR CHUNKING/LOOPING: 
      // This makes the app wait for one chunk to finish before sending the next.
      await flutterTts.awaitSpeakCompletion(true);

      await flutterTts.setPitch(pitch);
      await flutterTts.setSpeechRate(rate);
      await flutterTts.setLanguage(language);

      if (voiceJson != null) {
        Map<String, dynamic> voiceMap = jsonDecode(voiceJson);
        await flutterTts.setVoice(_safeVoiceMap(voiceMap));
      }

      await flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          ],
      );
    } catch (e) {
      print("Error loading settings: $e");
    }
  }

  Future<void> _savePhrases() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_phrases', phrases);
  }

  // -------------------------------------------------------------------------
  // CORE LOGIC: CHUNKING & LOOPING
  // -------------------------------------------------------------------------

  Future<void> _stopSpeaking() async {
    await flutterTts.stop();
    setState(() {
      _isPlaying = false;
      _currentPhrase = null;
    });
  }

  Future<void> _processText(String text) async {
    // 1. Stop anything currently playing
    await flutterTts.stop();
    
    setState(() {
      _isPlaying = true;
      _currentPhrase = text;
    });

    // 2. Clean text
    String cleanText = text.replaceAll("\n", " ");
    int length = cleanText.length;
    int chunkSize = 2000;

    // 3. Loop Logic
    do {
      int start = 0;
      
      // 4. Chunking Logic
      while (start < length) {
        // Check if user pressed stop during the loop
        if (!_isPlaying || _currentPhrase != text) return;

        int end = start + chunkSize;
        if (end > length) end = length;
        
        String chunk = cleanText.substring(start, end);
        
        // Speak and WAIT for it to finish (thanks to awaitSpeakCompletion)
        await flutterTts.speak(chunk);
        
        start += chunkSize;
      }

      // If not in loop mode, break after one full read-through
      if (!_isLoopMode) break;

    } while (_isPlaying && _isLoopMode && _currentPhrase == text);

    // Reset state when done
    if (_currentPhrase == text) {
      setState(() {
        _isPlaying = false;
        _currentPhrase = null;
      });
    }
  }

  // -------------------------------------------------------------------------

  void _addPhrase(String text) async {
    if (text.isNotEmpty) {
      setState(() => phrases.add(text));
      await _savePhrases();

      _textController.clear();
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _deletePhrase(int index) async {
    setState(() => phrases.removeAt(index));
    await _savePhrases(); 
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252540),
        title: const Text("New Phrase", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.sentences,
          maxLines: 5,
          minLines: 1,
          maxLength: 10000, // Increased limit since we now support chunking
          decoration: const InputDecoration(hintText: "What do you want to say?"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            onPressed: () => _addPhrase(_textController.text),
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  void _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettingsScreen(tts: flutterTts)),
    );
    _loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("TapTalk", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            // MIC AMPLIFIER BUTTON
            IconButton(
              tooltip: "Mic Amplifier",
              icon: const Icon(Icons.mic, color: Colors.white70),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MicAmplifierScreen()),
                );
              },
            ),
            // LOOP TOGGLE BUTTON
            IconButton(
              tooltip: "Loop Mode: ${_isLoopMode ? 'ON' : 'OFF'}",
              icon: Icon(
                Icons.repeat, 
                color: _isLoopMode ? const Color(0xFF00BFA6) : Colors.white38
              ),
              onPressed: () {
                setState(() => _isLoopMode = !_isLoopMode);
                // If we turn off loop while playing, stop immediately or let it finish?
                // Let's let it finish the current run.
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white70),
              onPressed: _openSettings,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.4,
            ),
            itemCount: phrases.length,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF3A86FF), // Blue
                      Color(0xFF8338EC), // Purple
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(2, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _processText(phrases[index]),
                    onLongPress: () => _deletePhrase(index),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          phrases[index],
                          textAlign: TextAlign.center,
                          maxLines: 4, 
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(blurRadius: 2, color: Colors.black26, offset: Offset(1, 1))
                            ]
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // FLOATING ACTION BUTTON
        // Shows STOP if playing, ADD if idle
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isPlaying ? _stopSpeaking : _showAddDialog,
          backgroundColor: _isPlaying ? Colors.redAccent : const Color(0xFF00BFA6),
          label: Text(
            _isPlaying ? "STOP" : "Add Phrase",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
          ),
          icon: Icon(
            _isPlaying ? Icons.stop : Icons.add,
            color: Colors.white
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SETTINGS SCREEN
// ---------------------------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  final FlutterTts tts;
  const SettingsScreen({super.key, required this.tts});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _pitch = 1.0;
  double _rate = 0.5;
  String _language = "en-US";
  List<String> _languages = [];
  List<Map<String, dynamic>> _voices = [];

  List<Map<String, dynamic>> _filteredVoices = []; 
  Map<String, dynamic>? _selectedVoice; 

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  Map<String, String> _safeVoiceMap(Map<dynamic, dynamic> voice) {
    final Map<String, String> safeMap = {};
    voice.forEach((key, value) {
      safeMap[key.toString()] = value.toString();
    });
    return safeMap;
  }

  Future<void> _initSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    var langs = await widget.tts.getLanguages;
    var rawVoices = await widget.tts.getVoices;
    List<Map<String, dynamic>> parsedVoices = [];
    if (rawVoices != null) {
      for (var v in rawVoices) {
        parsedVoices.add(Map<String, dynamic>.from(v as Map));
      }
    }

    String? savedVoiceJson = prefs.getString('voice');
    Map<String, dynamic>? loadedVoice;
    if (savedVoiceJson != null) {
      try {
        loadedVoice = jsonDecode(savedVoiceJson);
      } catch (e) { /* ignore */ }
    }

    double savedPitch = prefs.getDouble('pitch') ?? 1.0;
    double savedRate = prefs.getDouble('rate') ?? 0.5;
    String savedLang = prefs.getString('language') ?? "en-US";

    if (mounted) {
      setState(() {
        _languages = List<String>.from(langs);
        _voices = parsedVoices;
        _pitch = savedPitch;
        _rate = savedRate;
        _language = savedLang;
        _selectedVoice = loadedVoice;
        _filterVoices();
      });
    }
  }

  void _filterVoices() {
    if (!mounted) return;
    setState(() {
      _filteredVoices = _voices.where((voice) {
        String locale = voice['locale'].toString();
        return locale.contains(_language) || _language.contains(locale);
      }).toList();

      if (_selectedVoice != null) {
        String voiceLocale = _selectedVoice!['locale'].toString();
        if (!voiceLocale.contains(_language) && !_language.contains(voiceLocale)) {
          _selectedVoice = null;
        }
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pitch', _pitch);
    await prefs.setDouble('rate', _rate);
    await prefs.setString('language', _language);
    
    if (_selectedVoice != null) {
      await prefs.setString('voice', jsonEncode(_selectedVoice));
      await widget.tts.setVoice(_safeVoiceMap(_selectedVoice!));
    }
    
    await widget.tts.setPitch(_pitch);
    await widget.tts.setSpeechRate(_rate);
    await widget.tts.setLanguage(_language);
  }

  Future<void> _testConfiguration() async {
    await _saveSettings();
    await widget.tts.speak("Hello, this is my new voice.");
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Settings"),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle("Language"),
                _buildContainer(
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2D2D44),
                      style: const TextStyle(color: Colors.white),
                      value: _languages.contains(_language) ? _language : null,
                      hint: const Text("Select Language", style: TextStyle(color: Colors.grey)),
                      items: _languages.map((lang) {
                        return DropdownMenuItem<String>(
                          value: lang,
                          child: Text(lang),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _language = val;
                            _filterVoices(); 
                          });
                          _saveSettings();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                _buildSectionTitle("Specific Voice"),
                _buildContainer(
                  DropdownButtonHideUnderline(
                    child: DropdownButton<Map<String, dynamic>>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2D2D44),
                      style: const TextStyle(color: Colors.white),
                      value: _filteredVoices.contains(_selectedVoice) ? _selectedVoice : null,
                      hint: _filteredVoices.isEmpty 
                          ? const Text("No voices found", style: TextStyle(color: Colors.grey)) 
                          : const Text("Default Voice", style: TextStyle(color: Colors.grey)),
                      items: _filteredVoices.map((voice) {
                        return DropdownMenuItem<Map<String, dynamic>>(
                          value: voice,
                          child: Text(voice['name'] ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedVoice = val);
                        _saveSettings();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                _buildSectionTitle("Speed: ${_rate.toStringAsFixed(1)}"),
                _buildSlider(_rate, 0.0, 1.0, (val) { 
                  setState(() => _rate = val); 
                  _saveSettings();
                }),
                
                _buildSectionTitle("Pitch: ${_pitch.toStringAsFixed(1)}"),
                _buildSlider(_pitch, 0.5, 2.0, (val) { 
                  setState(() => _pitch = val); 
                  _saveSettings();
                }),
                
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _testConfiguration,
                    icon: const Icon(Icons.volume_up),
                    label: const Text("TEST CONFIGURATION", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 5),
      child: Text(
        title.toUpperCase(), 
        style: const TextStyle(
          color: Colors.white70, 
          fontSize: 14, 
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildContainer(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D44),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildSlider(double value, double min, double max, Function(double) onChanged) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: const Color(0xFF6C63FF),
        thumbColor: const Color(0xFF00BFA6),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: 15,
        onChanged: onChanged,
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// MIC AMPLIFIER SCREEN (NEW)
// ---------------------------------------------------------------------------
class MicAmplifierScreen extends StatefulWidget {
  const MicAmplifierScreen({super.key});

  @override
  State<MicAmplifierScreen> createState() => _MicAmplifierScreenState();
}

class _MicAmplifierScreenState extends State<MicAmplifierScreen> with SingleTickerProviderStateMixin {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isLooping = false; // <-- New Loop State
  double _amplification = 1.0;
  String? _recordedFilePath;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PURE DART TRUE AMPLIFIER (NO FFMPEG NEEDED)
  // ---------------------------------------------------------------------------
  Future<String?> _applyTrueAmplification(String originalPath, double multiplier) async {
    if (multiplier == 1.0) return originalPath; // No math needed

    try {
      File file = File(originalPath);
      Uint8List bytes = await file.readAsBytes();

      // 1. Find the "data" chunk in the WAV file
      int dataStartIndex = 44; // Default WAV header length
      for (int i = 0; i < bytes.length - 4; i++) {
        if (bytes[i] == 100 && bytes[i + 1] == 97 && bytes[i + 2] == 116 && bytes[i + 3] == 97) { // "data" in ASCII
          dataStartIndex = i + 8; // Skip "data" (4 bytes) + chunk size (4 bytes)
          break;
        }
      }

      // 2. Extract Header and PCM Data safely
      Uint8List header = bytes.sublist(0, dataStartIndex);
      // We copy dataBytes to a new list to ensure perfectly aligned memory for Int16List
      Uint8List dataBytes = Uint8List.fromList(bytes.sublist(dataStartIndex));
      
      // 3. Convert bytes to 16-bit integers (raw audio waves)
      Int16List pcmData = dataBytes.buffer.asInt16List();
      Int16List amplifiedPcm = Int16List(pcmData.length);

      // 4. Apply TRUE Amplification (Multiply & Clamp)
      for (int i = 0; i < pcmData.length; i++) {
        double sample = pcmData[i] * multiplier;

        // Clamp to 16-bit audio limits to create the "blown out" clipping effect naturally
        if (sample > 32767) {
          amplifiedPcm[i] = 32767;
        } else if (sample < -32768) {
          amplifiedPcm[i] = -32768;
        } else {
          amplifiedPcm[i] = sample.toInt();
        }
      }

      // 5. Stitch modified audio back together
      BytesBuilder builder = BytesBuilder();
      builder.add(header);
      builder.add(amplifiedPcm.buffer.asUint8List());

      // 6. Save as new temporary file
      String outPath = originalPath.replaceAll('.wav', '_amplified.wav');
      await File(outPath).writeAsBytes(builder.toBytes());
      
      return outPath;
    } catch (e) {
      print("Amplification Error: $e");
      return originalPath; // Fallback to original if something fails
    }
  }
  // ---------------------------------------------------------------------------

  Future<void> _toggleRecording() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
    }

    if (_isRecording) {
      // STOP RECORDING
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
      });
      
      if (path != null) {
        _playAudio();
      }
    } else {
      // START RECORDING
      if (await _audioRecorder.hasPermission()) {
        final Directory tempDir = await getTemporaryDirectory();
        final String path = '${tempDir.path}/raw_recording.wav'; // Must be WAV for True Amp

        // Configure recording to inherently filter noise & echo at the hardware level
        const config = RecordConfig(
          encoder: AudioEncoder.wav, // Changed to WAV
          noiseSuppress: true,
          echoCancel: true,
          autoGain: true, 
        );

        await _audioRecorder.start(config, path: path);
        setState(() {
          _isRecording = true;
          _recordedFilePath = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission denied.")),
        );
      }
    }
  }

  Future<void> _playAudio() async {
    if (_recordedFilePath == null) return;
    
    await _audioPlayer.stop();

    // 1. Process the audio waves mathematically
    String? finalPathToPlay = await _applyTrueAmplification(_recordedFilePath!, _amplification);

    // 2. Set loop mode based on the user's toggle
    await _audioPlayer.setReleaseMode(_isLooping ? ReleaseMode.loop : ReleaseMode.stop);

    // 3. Play at max system volume (since the file itself is now amplified)
    if (finalPathToPlay != null) {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(DeviceFileSource(finalPathToPlay));
    }
  }

  Future<void> _stopPlayback() async {
    await _audioPlayer.stop();
  }

  void _toggleLoop() {
    setState(() {
      _isLooping = !_isLooping;
    });
    // Apply immediately if audio is already playing
    _audioPlayer.setReleaseMode(_isLooping ? ReleaseMode.loop : ReleaseMode.stop);
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Mic Amplifier"),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            // REPEAT / LOOP BUTTON
            IconButton(
              tooltip: "Loop Playback: ${_isLooping ? 'ON' : 'OFF'}",
              icon: Icon(
                Icons.repeat,
                color: _isLooping ? const Color(0xFF00BFA6) : Colors.white38,
              ),
              onPressed: _toggleLoop,
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Noise Filter: ENABLED",
                  style: TextStyle(
                    color: Color(0xFF00BFA6),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 60),

                // BIG RED RECORDING BUTTON
                GestureDetector(
                  onTap: _toggleRecording,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        height: 150,
                        width: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording ? Colors.redAccent : const Color(0xFF252540),
                          boxShadow: _isRecording
                              ? [
                                  BoxShadow(
                                    color: Colors.redAccent.withOpacity(0.5 * _pulseController.value),
                                    blurRadius: 30 * _pulseController.value,
                                    spreadRadius: 15 * _pulseController.value,
                                  )
                                ]
                              : [
                                  const BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 10,
                                    offset: Offset(0, 5),
                                  )
                                ],
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          color: Colors.white,
                          size: 60,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  _isRecording 
                      ? "Recording... Tap to stop" 
                      : (_isPlaying ? "Playing Amplified Audio..." : "Tap to Record"),
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
                
                const SizedBox(height: 60),

                // TRUE AMPLIFICATION SLIDER
                Row(
                  children: [
                    const Icon(Icons.volume_down, color: Colors.white54),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF6C63FF),
                          thumbColor: const Color(0xFF00BFA6),
                        ),
                        child: Slider(
                          value: _amplification,
                          min: 1.0,
                          max: 10000.0,
                          divisions: 99,
                          label: "${_amplification.toInt()}x",
                          onChanged: (val) {
                            setState(() => _amplification = val);
                          },
                          // Re-process and restart audio when you let go of the slider
                          onChangeEnd: (val) {
                            if (_recordedFilePath != null && !_isRecording) {
                              _playAudio(); 
                            }
                          },
                        ),
                      ),
                    ),
                    const Icon(Icons.flash_on, color: Colors.yellowAccent),
                  ],
                ),
                Text(
                  "True Amplification: ${_amplification.toInt()}x",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 40),
                
                // REPLAY BUTTON
                if (_recordedFilePath != null && !_isRecording)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isPlaying ? Colors.redAccent : const Color(0xFF00BFA6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isPlaying ? _stopPlayback : _playAudio,
                    icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(_isPlaying ? "STOP" : "REPLAY", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}