import 'package:flutter/material.dart';

import '../locale_provider.dart';

/// Horizontal row of language chips rendered with the **autonym** of
/// each locale (how each language calls itself: "English", "Español",
/// "Français", …). Surfaces the example's i18n coverage at first
/// glance on the onboarding screen.
///
/// Why autonyms and not flags: a flag is a country, not a language —
/// 🇪🇸 excludes ~600M Spanish speakers in LATAM, 🇵🇹 invisibilises
/// Brazil, 🇩🇪 ignores Austria/Switzerland, etc. Apple / Google /
/// Microsoft pickers all use autonyms for the same reason.
class LanguagePickerRow extends StatelessWidget {
  const LanguagePickerRow({super.key});

  static const List<({String code, String autonym})> _languages = [
    (code: 'en', autonym: 'English'),
    (code: 'es', autonym: 'Español'),
    (code: 'fr', autonym: 'Français'),
    (code: 'de', autonym: 'Deutsch'),
    (code: 'it', autonym: 'Italiano'),
    (code: 'pt', autonym: 'Português'),
    (code: 'ca', autonym: 'Català'),
  ];

  @override
  Widget build(BuildContext context) {
    final locale = LocaleProvider.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.language,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final lang in _languages) ...[
            ChoiceChip(
              label: Text(lang.autonym),
              selected: locale.languageCode == lang.code,
              onSelected: (_) => locale.setLanguageCode(lang.code),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
