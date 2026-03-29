import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Handles all Gemini AI interactions for OmniTutor AI.
class AIService {
  // ── Socratic System Prompt ─────────────────────────────────────────────
  static const String _socraticSystemPrompt = '''
You are OmniTutor, a patient and encouraging AI tutor for students.
Your teaching philosophy is strictly Socratic:

CORE RULES:
1. NEVER solve the problem or give the final answer directly.
2. Instead, carefully look at the student's work in the image (when provided).
3. If you spot an error, DO NOT correct it outright. Ask a guiding question that leads the student to notice the mistake themselves. Example: "I see you wrote X here — can you walk me through how you got that?"
4. If the work looks correct so far, affirm their progress and ask what they think the next step is.
5. Break complex problems into small, digestible steps through questions.
6. Keep your responses concise — 2 to 4 sentences maximum.
7. Be warm, encouraging, and never condescending.
8. If you cannot read the image clearly, politely ask the student to hold the camera steadier or move closer.
9. When the student replies with text, remember our ENTIRE conversation and continue guiding them forward.

RECOGNIZING MASTERY:
- If the student successfully answers your guiding question and demonstrates they understand the concept, affirm them warmly.
- IMPORTANT: At the very end of such a "mastery" response, always include the exact tag: [MASTERY_ACHIEVED]

Your goal is to build the student's UNDERSTANDING and CONFIDENCE, not just get them to a correct answer.
''';

  GenerativeModel? _model;

  /// Lazily initialises the Gemini model using the key from the .env file.
  GenerativeModel _getModel() {
    if (_model != null) return _model!;

    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'your_api_key_here') {
      throw Exception(
          'GEMINI_API_KEY is missing or not set in your .env file.');
    }

    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(_socraticSystemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 512,
      ),
    );
    return _model!;
  }

  /// Starts a new [ChatSession] with the Socratic system prompt baked in.
  ///
  /// Call this once when the TutoringScreen opens. Store the returned session
  /// in state and pass it to [sendMessageStream] for every subsequent turn.
  ChatSession startChat() {
    return _getModel().startChat();
  }

  /// Unified streaming send for both image+text and text-only turns.
  ///
  /// - If [imageBytes] is provided → multimodal turn (camera snapshot).
  /// - If [imageBytes] is null → text-only turn (student types a reply).
  ///
  /// Yields response text chunks as they arrive so the UI can stream them.
  Stream<String> sendMessageStream({
    required ChatSession session,
    Uint8List? imageBytes,
    String userText = 'Please look at my work and help me.',
    String selectedLanguage = 'English',
    String mimeType = 'image/jpeg',
  }) async* {
    // ── Prepend Critical Language Instruction ──────────────────────────
    final String languagePrompt =
        'CRITICAL: You MUST provide your entire response (explanations, guiding questions, and mastery affirmations) strictly in $selectedLanguage. DO NOT respond in English or any other language unless asked for a translation. Translate all technical terms if appropriate.\n\n';

    final Content content;
    if (imageBytes != null) {
      content = Content.multi([
        DataPart(mimeType, imageBytes),
        TextPart(languagePrompt + userText),
      ]);
    } else {
      content = Content.text(languagePrompt + userText);
    }

    try {
      final responseStream = session.sendMessageStream(content);
      await for (final chunk in responseStream) {
        final text = chunk.text;
        if (text != null && text.isNotEmpty) {
          yield text;
        }
      }
    } on GenerativeAIException catch (e) {
      throw Exception('AI Error: ${e.message}');
    }
  }
}
