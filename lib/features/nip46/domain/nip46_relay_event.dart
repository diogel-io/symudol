class Nip46InboundRelayEvent {
  final String eventId;
  final String senderPubkey;
  // The remote-signer pubkey from the #p tag — identifies which session owns this event.
  final String recipientPubkey;
  final String encryptedContent;
  final String relay;
  final int createdAt;

  const Nip46InboundRelayEvent({
    required this.eventId,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.encryptedContent,
    required this.relay,
    required this.createdAt,
  });
}
