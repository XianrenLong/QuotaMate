enum AiProvider { gpt, claude }

extension ProviderName on AiProvider {
  String get label => this == AiProvider.gpt ? 'GPT' : 'Claude';
}
