import '../../models/host_user.dart';

/// Asks the host application who a set of chat ids belong to.
///
/// Chat stores ids; names and faces live in the host's directory. When
/// the SDK needs to paint a person it has no profile for — the other
/// side of a one-to-one room, the sender prefix of a group message, the
/// avatar next to a bubble, the subject of a system line — it collects
/// the unknown ids and asks once, in a batch.
///
/// The contract:
///
/// - **Batched.** The SDK groups ids over a short window and calls this
///   with the whole set; answering one id per call is allowed but wastes
///   the batching.
/// - **Keyed by the requested id.** Every entry of the returned map must
///   be keyed by an id from [ids]; extra keys are ignored.
/// - **Partial answers are fine.** An id left out of the map is treated
///   as *not answered yet* and may be asked about again later.
/// - **Say when nobody is there.** An id that has no person behind it —
///   deleted, outside the viewer's directory — should come back as
///   [HostUser.missing], not be omitted. That is what stops the SDK from
///   asking forever.
/// - **Never throws for a missing person.** A thrown failure is a
///   transport failure: the SDK logs it and retries later.
///
/// ```dart
/// ChatUiAdapter(
///   client: client,
///   currentUser: me,
///   userDirectoryResolver: (ids) async {
///     final people = await contacts.lookup(ids.toList());
///     return {
///       for (final id in ids)
///         id: people[id] == null
///             ? HostUser.missing(id)
///             : HostUser(
///                 id: id,
///                 displayName: people[id]!.name,
///                 avatarUrl: people[id]!.photoUrl,
///               ),
///     };
///   },
/// );
/// ```
typedef UserDirectoryResolver =
    Future<Map<String, HostUser>> Function(Set<String> ids);
