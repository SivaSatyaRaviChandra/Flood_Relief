/// Voice input boundary.
///
/// The rest of the application depends only on this interface. Concrete
/// implementations live in `speech/`.
library;

import '../../core/errors/app_error.dart';

/// Optional voice input for SOS descriptions.
///
/// Returns the recognized text, or null when the user cancelled. Throws
/// [AppError] with kind [AppErrorKind.speechRecognitionFailure] when speech
/// input is unavailable on the current device/configuration.
abstract class SpeechService {
  Future<SpeechRecognitionResult> recognize();
}

sealed class SpeechRecognitionResult {
  const SpeechRecognitionResult();
}

class SpeechRecognized extends SpeechRecognitionResult {
  const SpeechRecognized(this.text);
  final String text;
}

class SpeechCancelled extends SpeechRecognitionResult {
  const SpeechCancelled();
}

/// Clean fallback used when no speech provider is available. It never throws
/// and never fakes a result — it reports that speech input is unavailable.
class UnavailableSpeechService implements SpeechService {
  const UnavailableSpeechService();

  @override
  Future<SpeechRecognitionResult> recognize() async {
    throw const AppError(
      AppErrorKind.speechRecognitionFailure,
      'Offline speech input is not available on this build. '
      'Type the description instead.',
    );
  }
}