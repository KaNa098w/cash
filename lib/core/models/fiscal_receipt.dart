class FiscalReceipt {
  const FiscalReceipt({
    required this.id,
    required this.status,
    required this.printable,
    this.ticketPrintUrl,
    this.pollAfterSeconds = 2,
    this.errorMessage,
    this.ticketUrl,
    this.offlineMode = false,
    this.ofdDeliveryStatus,
  });

  final String id;
  final String status;
  final bool printable;
  final String? ticketPrintUrl;
  final int pollAfterSeconds;
  final String? errorMessage;
  final String? ticketUrl;
  final bool offlineMode;
  final String? ofdDeliveryStatus;

  bool get isPending => status == 'pending' || status == 'processing';
  bool get canPrint => status == 'succeeded' && printable;
  bool get hasFailed => status == 'failed' || status == 'needs_review';

  factory FiscalReceipt.fromJson(Map<String, dynamic> json) {
    bool asBool(dynamic value) =>
        value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == 'true';
    final poll = int.tryParse((json['poll_after_seconds'] ?? '').toString());
    return FiscalReceipt(
      id: (json['id'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString().toLowerCase(),
      printable: asBool(json['printable']),
      ticketPrintUrl: json['ticket_print_url']?.toString(),
      pollAfterSeconds: (poll ?? 2).clamp(1, 30),
      errorMessage:
          (json['last_error'] ?? json['error_message'] ?? json['message'])
              ?.toString(),
      ticketUrl: json['ticket_url']?.toString(),
      offlineMode: asBool(json['offline_mode']),
      ofdDeliveryStatus: json['ofd_delivery_status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'printable': printable,
        'ticket_print_url': ticketPrintUrl,
        'poll_after_seconds': pollAfterSeconds,
        'error_message': errorMessage,
        'ticket_url': ticketUrl,
        'offline_mode': offlineMode,
        'ofd_delivery_status': ofdDeliveryStatus,
      };
}
