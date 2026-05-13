/// Result of an attachment upload containing the server-assigned ID and optional URL.
class AttachmentUploadResult {
  final String attachmentId;
  final String? url;
  final String? metadata;
  final Map<String, dynamic> raw;

  const AttachmentUploadResult({
    required this.attachmentId,
    this.url,
    this.metadata,
    required this.raw,
  });

  @override
  String toString() => 'AttachmentUploadResult($attachmentId)';
}
