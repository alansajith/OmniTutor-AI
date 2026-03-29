import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:confetti/confetti.dart';
import '../widgets/tutor_widgets.dart';
import '../services/language_service.dart';

class TutoringScreen extends StatefulWidget {
  const TutoringScreen({super.key});

  @override
  State<TutoringScreen> createState() => _TutoringScreenState();
}

class _TutoringScreenState extends State<TutoringScreen> {
  // ── Camera ─────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isCameraLoading = false;
  String? _cameraError;

  // ── Services ───────────────────────────────────────────────────────────
  final _auth = FirebaseAuth.instance;
  final _firestoreService = FirestoreService();
  final _aiService = AIService();
  final _authService = AuthService();
  final FlutterTts _tts = FlutterTts();

  // ── AI Chat Session ────────────────────────────────────────────────────
  /// Gemini ChatSession — persists context for the whole tutoring session.
  late ChatSession _chatSession;

  // ── UI State ───────────────────────────────────────────────────────────
  final List<Map<String, String>> _chatMessages = [];
  bool _isStreaming = false;
  bool _isSaving = false;
  bool _isMuted = false;
  int? _streamingBubbleIndex;

  // ── Speech-to-Text ─────────────────────────────────────────────────────
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  // ── Input ──────────────────────────────────────────────────────────────
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ── Gamification ───────────────────────────────────────────────────────
  late ConfettiController _confettiController;

  // ── Language Support ───────────────────────────────────────────────────
  String _selectedLanguage = 'English';
  String _selectedLocale = 'en-US';

  @override
  void initState() {
    super.initState();
    _chatSession = _aiService.startChat();
    _initTTS();
    _initSpeech();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _tts.stop();
    _confettiController.dispose();
    super.dispose();
  }

  // ── TTS ────────────────────────────────────────────────────────────────
  Future<void> _initTTS() async {
    await _tts.setLanguage('en-US');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
  }

  // ── Speech ─────────────────────────────────────────────────────────────
  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (e) => setState(() => _isListening = false),
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    // Re-initialize each time in case permissions changed since app launch.
    // speech_to_text handles the iOS/Android permission prompt internally.
    bool available = _speechAvailable;
    if (!available) {
      available = await _speech.initialize(
        onError: (e) => setState(() => _isListening = false),
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      _speechAvailable = available;
    }

    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Speech recognition unavailable — check microphone permissions in Settings.'),
          ),
        );
      }
      return;
    }

    setState(() => _isListening = true);
    try {
      await _speech.listen(
        onResult: (result) {
          if (mounted) {
            setState(() {
              _textController.text = result.recognizedWords;
              _textController.selection = TextSelection.fromPosition(
                TextPosition(offset: _textController.text.length),
              );
            });
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: _selectedLocale.replaceAll('-', '_'),
      );
    } catch (e) {
      setState(() => _isListening = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speech error: $e')),
        );
      }
    }
  }

  Future<void> _speak(String text) async {
    if (_isMuted || text.isEmpty) return;
    try {
      await _tts.stop();
      // Dynamically set language accent to match AI response
      await _tts.setLanguage(_selectedLocale);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS Error ($_selectedLocale): $e');
    }
  }

  // ── Camera ─────────────────────────────────────────────────────────────
  Future<void> _initializeCamera() async {
    if (mounted) setState(() => _isCameraLoading = true);
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _cameraError = 'No cameras found on this device.';
          _isCameraLoading = false;
        });
        return;
      }
      _cameraController = CameraController(
        _cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
        _isCameraLoading = false;
      });
    } catch (e) {
      setState(() {
        _cameraError = 'Camera error: ${e.toString()}';
        _isCameraLoading = false;
      });
    }
  }

  // ── Core Message Sender ────────────────────────────────────────────────
  /// Unified message sender.
  /// If [imageBytes] is provided → multimodal (camera) turn.
  /// Otherwise → text-only reply turn.
  Future<void> _sendMessage({Uint8List? imageBytes}) async {
    if (_isStreaming) return;

    final String userText = _textController.text.trim().isNotEmpty
        ? _textController.text.trim()
        : (imageBytes != null ? 'Please look at my work and help me.' : '');

    if (userText.isEmpty && imageBytes == null) return;

    _textController.clear();

    // 1. Add user bubble
    setState(() {
      _isStreaming = true;
      _chatMessages.add({
        'role': 'user',
        'text': imageBytes != null
            ? '📷 ${userText == 'Please look at my work and help me.' ? 'Image captured' : userText}'
            : userText,
      });
      // 2. Add empty AI bubble, fill letter-by-letter
      _chatMessages.add({'role': 'ai', 'text': ''});
      _streamingBubbleIndex = _chatMessages.length - 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // 3. Stream Gemini response
    final StringBuffer fullResponse = StringBuffer();
    try {
      final stream = _aiService.sendMessageStream(
        session: _chatSession,
        imageBytes: imageBytes,
        userText: userText,
        selectedLanguage: _selectedLanguage,
      );

      await for (final String chunk in stream) {
        fullResponse.write(chunk);
        if (mounted && _streamingBubbleIndex != null) {
          // Clean text for real-time display
          String cleanText = fullResponse.toString();
          cleanText = cleanText.replaceAll('[MASTERY_ACHIEVED]', '').trim();

          setState(() {
            _chatMessages[_streamingBubbleIndex!] = {
              'role': 'ai',
              'text': cleanText,
            };
          });
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());
        }
      }

      // 4. Post-stream logic
      final String aiTextRaw = fullResponse.toString();
      final bool masteryAchieved = aiTextRaw.contains('[MASTERY_ACHIEVED]');
      final String aiText =
          aiTextRaw.replaceAll('[MASTERY_ACHIEVED]', '').trim();

      if (aiText.isNotEmpty) {
        _speak(aiText);

        if (masteryAchieved) {
          _confettiController.play();
          final User? user = _auth.currentUser;
          if (user != null) {
            await _firestoreService.awardPoints(user.uid, 100);
          }
        }

        if (imageBytes != null) {
          setState(() => _isSaving = true);
          final User? user = _auth.currentUser;
          if (user != null) {
            await _firestoreService.saveSession(
              uid: user.uid,
              subject: 'Multimodal Session',
              aiResponse: aiText,
            );
            await _firestoreService.awardPoints(user.uid, 50);
          }
          if (mounted) setState(() => _isSaving = false);
        }
      }
    } catch (e) {
      debugPrint('Gemini Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection lost. Please try again.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _streamingBubbleIndex = null;
        });
      }
    }
  }

  /// Captures a frame then calls [_sendMessage] with the image.
  Future<void> _onCaptureAndSend() async {
    if (!_isCameraInitialized || _cameraController == null) {
      await _initializeCamera();
      return;
    }

    XFile? imageFile;
    try {
      imageFile = await _cameraController!.takePicture();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture image: $e')),
        );
      }
      return;
    }

    final Uint8List imageBytes = await imageFile.readAsBytes();
    await _sendMessage(imageBytes: imageBytes);
  }

  /// Sends the current text from the input field (text-only turn).
  void _onSendText() {
    if (_textController.text.trim().isEmpty) return;
    _sendMessage();
  }

  // ── Helpers ────────────────────────────────────────────────────────────
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 32,
            ),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
              ).createShader(bounds),
              child: const Text(
                'OmniTutor AI',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Language Selector
          _buildLanguageSelector(),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
              color: const Color(0xFF8A8AB0),
              size: 20,
            ),
            tooltip: _isMuted ? 'Unmute' : 'Mute',
            onPressed: () {
              setState(() => _isMuted = !_isMuted);
              if (_isMuted) _tts.stop();
            },
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    color: Color(0xFF00D4FF), strokeWidth: 1.5),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout_outlined,
                color: Color(0xFF8A8AB0), size: 20),
            tooltip: 'Sign out',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await _authService.signOut();
              navigator.pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // ── TOP: Camera Preview ──────────────────────────────────────
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                const Color(0xFF6C63FF).withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF)
                                  .withValues(alpha: 0.08),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: _buildCameraPreview(),
                      ),
                      // Corner brackets
                      const Positioned(
                        top: 12,
                        left: 12,
                        child: CornerBracket(color: Color(0xFF6C63FF)),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(3.14159),
                          child: const CornerBracket(color: Color(0xFF6C63FF)),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationX(3.14159),
                          child: const CornerBracket(color: Color(0xFF6C63FF)),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationZ(3.14159),
                          child: const CornerBracket(color: Color(0xFF6C63FF)),
                        ),
                      ),
                      // Status chip
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _isStreaming
                                        ? Colors.orangeAccent
                                        : const Color(0xFF00D4FF),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isStreaming
                                      ? 'THINKING...'
                                      : 'LIVE  •  Point at your notes',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── MIDDLE: Chat Log ────────────────────────────────────────
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              color: const Color(0xFF6C63FF)
                                  .withValues(alpha: 0.7),
                              size: 14),
                          const SizedBox(width: 8),
                          Text(
                            'Conversation',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Divider(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _chatMessages.isEmpty
                          ? _buildEmptyChat()
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              itemCount: _chatMessages.length,
                              itemBuilder: (context, index) {
                                final msg = _chatMessages[index];
                                final isStreaming = _isStreaming &&
                                    index == _streamingBubbleIndex;
                                return ChatBubble(
                                  text: msg['text'] ?? '',
                                  isAI: msg['role'] == 'ai',
                                  isStreaming: isStreaming,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              // ── BOTTOM: Input Bar ────────────────────────────────────────
              _buildInputBar(),
            ],
          ),
          // ── CELEBRATION OVERLAY ──────────────────────────────────────────────
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
                Color(0xFF6C63FF),
                Color(0xFF00D4FF),
              ],
              gravity: 0.2,
              numberOfParticles: 20,
              strokeWidth: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_isCameraLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF6C63FF)),
            SizedBox(height: 16),
            Text('Initializing camera...',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    if (_cameraError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined,
                size: 52, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(_cameraError!,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    if (_isCameraInitialized && _cameraController != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CameraPreview(_cameraController!),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.power_settings_new,
                    color: Colors.redAccent, size: 20),
              ),
              onPressed: () async {
                await _cameraController?.dispose();
                if (mounted) {
                  setState(() {
                    _isCameraInitialized = false;
                    _cameraController = null;
                  });
                }
              },
              tooltip: 'Turn Off Camera',
            ),
          ),
        ],
      );
    }
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 36, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 6),
            Text(
              'Camera is Off',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _initializeCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                foregroundColor: const Color(0xFF6C63FF),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  ),
                ),
              ),
              icon: const Icon(Icons.videocam_outlined, size: 16),
              label:
                  const Text('Turn On Camera', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<String>(
        value: _selectedLanguage,
        icon: const Icon(Icons.language, color: Color(0xFF6C63FF), size: 18),
        underline: const SizedBox(),
        dropdownColor: const Color(0xFF1A1A2E),
        style: const TextStyle(color: Colors.white70, fontSize: 13),
        onChanged: (String? newValue) {
          if (newValue != null) {
            setState(() {
              _selectedLanguage = newValue;
              _selectedLocale = LanguageConfig.getLocale(newValue);
            });
          }
        },
        items:
            LanguageConfig.names.map<DropdownMenuItem<String>>((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 30, 30, 44),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Camera button ──────────────────────────────────────────
            IconButton(
              icon: Icon(
                Icons.camera_alt_outlined,
                color: Colors.white.withValues(alpha: 0.5),
                size: 26,
              ),
              tooltip: 'Capture & Ask',
              onPressed: _isStreaming ? null : _onCaptureAndSend,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            // ── Text input area (Seamless) ──────────────────────────────
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Mic button
                  GestureDetector(
                    onTap: _isStreaming ? null : _toggleListening,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none_rounded,
                        size: 24,
                        color: _isListening
                            ? Colors.redAccent
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      enabled: !_isStreaming,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _onSendText(),
                      decoration: InputDecoration(
                        hintText: 'Reply to the tutor...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── Send button (Circular) ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildSendButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    return GestureDetector(
      onTap: _isStreaming ? null : _onSendText,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _isStreaming
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: _isStreaming ? Colors.white.withValues(alpha: 0.05) : null,
          boxShadow: [
            if (!_isStreaming)
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Center(
          child: _isStreaming
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Color(0xFF6C63FF),
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _buildEmptyChat() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: 0.15,
              child: Image.asset(
                'assets/images/logo.png',
                width: 90,
                height: 90,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap 📷 to analyse your notes,\nor type a reply to the tutor.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── (Supporting widgets moved to tutor_widgets.dart) ────────────────────────
