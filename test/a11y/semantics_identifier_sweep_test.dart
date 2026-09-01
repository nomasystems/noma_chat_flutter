import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source sweep over `lib/`: every interactive `Semantics` node the package
/// paints must publish a name.
///
/// The other tests in this directory are a registry — they assert that the
/// names we already know about are reachable from the semantics tree. They
/// cannot see a control that ships without one, which is how a button ends
/// up in a native dump with a label and no `AXUniqueId`. This test reads the
/// source instead of the tree, so a new `Semantics(button: …)` without an
/// `identifier:` fails here the day it is written.
///
/// A node counts as interactive when it declares a role or an action a
/// driver can point at: `button`, `link`, `textField`, `slider`, `onTap`,
/// `onLongPress` or `customSemanticsActions`.
void main() {
  test('every interactive Semantics under lib/ publishes an identifier', () {
    final offenders = <String>[];

    for (final file in _dartSources()) {
      final path = file.path;
      final source = _withoutComments(file.readAsStringSync());
      for (final match in _semanticsCall.allMatches(source)) {
        final args = _topLevelArguments(source, match.end - 1);
        final roles = args
            .where((arg) => _interactiveRoles.any(arg.startsWith))
            .map((arg) => arg.split(':').first)
            .toList();
        if (roles.isEmpty) continue;
        if (args.any((arg) => arg.startsWith('identifier:'))) continue;
        if (_unnamedByDesign.containsKey(path)) continue;
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('$path:$line declares ${roles.join(', ')}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These Semantics nodes are addressable by a user but not by a '
          'driver:\n  ${offenders.join('\n  ')}\n\n'
          'Add `identifier:` to the node that is already there — never nest a '
          'second Semantics around it — and publish the same literal as the '
          'widget\'s `ValueKey`, per CONVENTIONS.md 10.11. Rows of a '
          'collection interpolate their own id through a shared helper '
          '(`messageBubbleSemanticsId`, `contactSuggestionSemanticsId`, …) so '
          'two rows never answer to one name; when the widget is handed no id '
          'to interpolate, pass `null` and it publishes no name rather than an '
          'ambiguous one.\n\n'
          'A control that genuinely cannot carry a name goes in '
          '`_unnamedByDesign` at the top of this file, keyed by its path and '
          'carrying the reason. That list is for controls with no identity to '
          'publish, not for controls nobody has got round to naming.',
    );
  });

  test(
    'every interactive Material button under lib/ publishes an identifier',
    () {
      final offenders = <String>[];
      final deferred = <String, int>{};

      for (final file in _dartSources()) {
        final path = file.path;
        if (_unnamedByDesign.containsKey(path)) continue;
        final exempt = _materialControlsNotYetNamed.containsKey(path);
        final source = _withoutComments(file.readAsStringSync());
        final named = _namedSemanticsSpans(source);
        for (final match in _materialButton.allMatches(source)) {
          final args = _topLevelArguments(source, match.end - 1);
          final callbacks = args
              .where((arg) => _interactiveCallbacks.any(arg.startsWith))
              .where((arg) => _argumentValue(arg) != 'null')
              .map((arg) => arg.split(':').first)
              .toList();
          if (callbacks.isEmpty) continue;
          if (named.any((span) => span.contains(match.start))) continue;
          if (exempt) {
            deferred[path] = (deferred[path] ?? 0) + 1;
            continue;
          }
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add(
            '$path:$line ${match.group(1)} takes ${callbacks.join(', ')}',
          );
        }
      }

      final drifted = <String>[];
      _materialControlsNotYetNamed.forEach((path, entry) {
        final found = deferred[path] ?? 0;
        if (found != entry.count) {
          drifted.add('$path defers ${entry.count} but holds $found');
        }
      });
      expect(
        drifted,
        isEmpty,
        reason:
            'The deferral list is a headcount, not a blanket pass:\n  '
            '${drifted.join('\n  ')}\n\n'
            'A file that holds MORE unnamed buttons than it defers has just '
            'gained one — name it per CONVENTIONS.md 10.11 instead of raising '
            'the count. A file that holds FEWER has had one named or removed: '
            'lower the count, and drop the entry once it reaches zero.',
      );

      expect(
        offenders,
        isEmpty,
        reason:
            'These Material buttons are addressable by a user but not by a '
            'driver:\n  ${offenders.join('\n  ')}\n\n'
            'Wrap the control in a `Semantics(identifier: …, button: true, '
            'label: …)` and publish the same literal as its `ValueKey`, per '
            'CONVENTIONS.md 10.11 — the composer, the camera screen and the '
            'voice overlay all read that way. Rows of a collection interpolate '
            'their own id through a shared helper (`roomTileSemanticsId`, '
            '`messageBubbleSemanticsId`, …) so two rows never answer to one '
            'name.\n\n'
            'A file whose buttons are known to be unnamed and are not driven '
            'yet goes in `_materialControlsNotYetNamed`, carrying the surface '
            'it belongs to. That list defers the work; it does not bless it.',
      );
    },
  );

  test('every exempted path still points at a real file', () {
    for (final path in [
      ..._unnamedByDesign.keys,
      ..._materialControlsNotYetNamed.keys,
    ]) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason:
            '$path is exempted from the identifier sweep but no longer '
            'exists. Drop the entry.',
      );
    }
  });
}

/// Interactive `Semantics` nodes that deliberately publish no name, keyed by
/// path and carrying the reason. See the failure message above before adding
/// to it.
const Map<String, String> _unnamedByDesign = {};

/// How many unnamed Material buttons a file is allowed to hold today, and
/// which surface they belong to. Unlike [_unnamedByDesign] these are
/// nameable. The count is exact in both directions: an eleventh button
/// added to a file that defers ten fails the sweep, and so does a file whose
/// buttons have since been named without lowering the number.
const Map<String, _DeferredControls> _materialControlsNotYetNamed = {
  'lib/src/ui/widgets/blocked_users_view.dart': _DeferredControls(
    1,
    'Per-row unblock button of the blocked-contacts list.',
  ),
  'lib/src/ui/widgets/chat_room_options_menu.dart': _DeferredControls(
    2,
    'Confirmation buttons of the room options sheet.',
  ),
  'lib/src/ui/widgets/group_info_page.dart': _DeferredControls(
    4,
    'Edit and confirm buttons of the group name and description fields.',
  ),
  'lib/src/ui/widgets/group_members_view.dart': _DeferredControls(
    1,
    'Per-member overflow button of the group members list.',
  ),
  'lib/src/ui/widgets/group_setup_page.dart': _DeferredControls(
    2,
    'Avatar and search buttons of the group creation flow.',
  ),
  'lib/src/ui/widgets/member_picker_sheet.dart': _DeferredControls(
    1,
    'Confirm button of the member picker sheet.',
  ),
  'lib/src/ui/widgets/message_forward_sheet.dart': _DeferredControls(
    1,
    'Send button of the forward sheet.',
  ),
  'lib/src/ui/widgets/profile_settings_page.dart': _DeferredControls(
    1,
    'Avatar edit button of the profile screen.',
  ),
  'lib/src/ui/widgets/report_message_dialog.dart': _DeferredControls(
    2,
    'Cancel and submit buttons of the report dialog.',
  ),
  'lib/src/ui/widgets/room_search_bar.dart': _DeferredControls(
    1,
    'Clear button of the room list search field.',
  ),
};

/// One entry of [_materialControlsNotYetNamed].
class _DeferredControls {
  const _DeferredControls(this.count, this.surface);

  /// Unnamed Material buttons the file holds today.
  final int count;

  /// Surface those buttons belong to.
  final String surface;
}

/// Material widgets whose whole purpose is to be tapped. A `Semantics` node
/// is not involved, so the sweep above cannot see them: an `IconButton` with
/// a tooltip reads fine to a screen reader and still lands in a native dump
/// without an `AXUniqueId`.
final RegExp _materialButton = RegExp(
  r'\b(IconButton|InkWell|InkResponse|TextButton|ElevatedButton'
  r'|OutlinedButton|FilledButton|FloatingActionButton|RawMaterialButton'
  r'|CupertinoButton)(<[^<>()]*>)?\s*\(',
);

const List<String> _interactiveCallbacks = [
  'onPressed:',
  'onTap:',
  'onLongPress:',
  'onChanged:',
  'onSelected:',
];

/// Character ranges covered by a `Semantics(` call that already publishes an
/// identifier, so a button nested inside one is not reported twice.
List<Range> _namedSemanticsSpans(String source) {
  final spans = <Range>[];
  for (final match in _semanticsCall.allMatches(source)) {
    final args = _topLevelArguments(source, match.end - 1);
    if (args.any((arg) => arg.startsWith('identifier:'))) {
      spans.add(Range(match.start, _endOfBracketed(source, match.end - 1)));
    }
  }
  return spans;
}

/// Half-open character range of a source construct.
class Range {
  const Range(this.start, this.end);
  final int start;
  final int end;
  bool contains(int offset) => offset >= start && offset < end;
}

/// Value half of a `name: value` argument, trimmed.
String _argumentValue(String argument) {
  final colon = argument.indexOf(':');
  return colon < 0 ? '' : argument.substring(colon + 1).trim();
}

const List<String> _interactiveRoles = [
  'button:',
  'link:',
  'textField:',
  'slider:',
  'onTap:',
  'onLongPress:',
  'customSemanticsActions:',
];

/// Matches the `Semantics(` constructor and not `MergeSemantics(`,
/// `ExcludeSemantics(` or `BlockSemantics(`: the word boundary cannot fall
/// between two identifier characters.
final RegExp _semanticsCall = RegExp(r'\bSemantics\s*\(');

Iterable<File> _dartSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

/// Top-level arguments of the call whose opening parenthesis is at
/// [openParen], trimmed. Nested calls, collections and string literals are
/// skipped whole, so a comma inside one of them does not split an argument.
List<String> _topLevelArguments(String source, int openParen) {
  final args = <String>[];
  var start = openParen + 1;
  var i = openParen + 1;
  while (i < source.length) {
    final char = source[i];
    if (char == '"' || char == "'") {
      i = _endOfStringLiteral(source, i);
      continue;
    }
    if (char == '(' || char == '[' || char == '{') {
      i = _endOfBracketed(source, i);
      continue;
    }
    if (char == ')') {
      args.add(source.substring(start, i));
      break;
    }
    if (char == ',') {
      args.add(source.substring(start, i));
      start = i + 1;
    }
    i++;
  }
  return [
    for (final arg in args)
      if (arg.trim().isNotEmpty) arg.trim(),
  ];
}

/// Index just past the closing quote of the literal opening at [start],
/// handling raw and triple-quoted strings and `${…}` interpolation.
int _endOfStringLiteral(String source, int start) {
  final raw = start > 0 && source[start - 1] == 'r';
  final quote = source[start];
  final terminator = source.startsWith(quote * 3, start) ? quote * 3 : quote;
  var i = start + terminator.length;
  while (i < source.length) {
    if (!raw && source[i] == r'\') {
      i += 2;
      continue;
    }
    if (!raw && source.startsWith(r'${', i)) {
      i = _endOfBracketed(source, i + 1);
      continue;
    }
    if (source.startsWith(terminator, i)) return i + terminator.length;
    i++;
  }
  return source.length;
}

/// Index just past the bracket that closes the one at [start].
int _endOfBracketed(String source, int start) {
  var depth = 0;
  var i = start;
  while (i < source.length) {
    final char = source[i];
    if (char == '"' || char == "'") {
      i = _endOfStringLiteral(source, i);
      continue;
    }
    if (char == '(' || char == '[' || char == '{') {
      depth++;
    } else if (char == ')' || char == ']' || char == '}') {
      depth--;
      if (depth == 0) return i + 1;
    }
    i++;
  }
  return source.length;
}

/// Blanks out `//` and `/* */` comments, keeping newlines so the reported
/// line numbers stay those of the file on disk. A `Semantics(` written in a
/// doc comment is documentation, not a control.
String _withoutComments(String source) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    if (char == '"' || char == "'") {
      final end = _endOfStringLiteral(source, i);
      buffer.write(source.substring(i, end));
      i = end;
      continue;
    }
    if (source.startsWith('//', i)) {
      final newline = source.indexOf('\n', i);
      if (newline < 0) break;
      buffer.write('\n');
      i = newline + 1;
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final skipped = end < 0
          ? source.substring(i)
          : source.substring(i, end + 2);
      buffer.write('\n' * '\n'.allMatches(skipped).length);
      i = end < 0 ? source.length : end + 2;
      continue;
    }
    buffer.write(char);
    i++;
  }
  return buffer.toString();
}
