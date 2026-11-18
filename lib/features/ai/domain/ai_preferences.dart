import 'package:aura_hub/features/ai/domain/ai_language.dart';

/// Local, profile-scoped AI preferences.
///
/// Contains NO secret and NO external connection claim. Consent starts false
/// and can only become true through an explicit user action.
class AiPreferences {
  const AiPreferences({
    this.language = AiLanguage.auto,
    this.consentGranted = false,
    this.selectedProviderId,
    this.activeConversationId,
  });

  final AiLanguage language;
  final bool consentGranted;
  final String? selectedProviderId;
  final String? activeConversationId;

  AiPreferences copyWith({
    AiLanguage? language,
    bool? consentGranted,
    String? selectedProviderId,
    String? activeConversationId,
    bool clearSelectedProvider = false,
    bool clearActiveConversation = false,
  }) {
    return AiPreferences(
      language: language ?? this.language,
      consentGranted: consentGranted ?? this.consentGranted,
      selectedProviderId: clearSelectedProvider
          ? null
          : selectedProviderId ?? this.selectedProviderId,
      activeConversationId: clearActiveConversation
          ? null
          : activeConversationId ?? this.activeConversationId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'language': language.code,
        'consentGranted': consentGranted,
        if (selectedProviderId != null)
          'selectedProviderId': selectedProviderId,
        if (activeConversationId != null)
          'activeConversationId': activeConversationId,
      };

  factory AiPreferences.fromJson(Map<String, dynamic> json) {
    return AiPreferences(
      // AURA detects the language from every message, so a user never has to
      // choose one. Older profiles that stored a fixed language are migrated
      // to Auto on load.
      language: AiLanguage.auto,
      consentGranted: json['consentGranted'] == true,
      selectedProviderId: json['selectedProviderId'] as String?,
      activeConversationId: json['activeConversationId'] as String?,
    );
  }
}
