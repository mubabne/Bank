class BankTransaction {
  const BankTransaction({
    required this.gmailMessageId,
    required this.title,
    required this.category,
    required this.date,
    required this.amount,
    this.currency = 'MNT',
    this.databaseId,
    this.description,
    this.emailSubject,
    this.emailSender,
    this.emailSnippet,
    this.source = 'gmail',
  });

  factory BankTransaction.fromDatabase(Map<String, dynamic> row) {
    return BankTransaction(
      databaseId: row['id'] as String?,
      gmailMessageId: row['gmail_message_id'] as String? ?? '',
      title:
          row['merchant_name'] as String? ??
          row['description'] as String? ??
          'Bank transaction',
      description: row['description'] as String?,
      category: row['category'] as String? ?? 'Bank activity',
      date: DateTime.parse(row['transacted_at'] as String),
      amount: _asDouble(row['amount']),
      currency: row['currency'] as String? ?? 'MNT',
      source: row['source'] as String? ?? 'gmail',
      emailSubject: row['email_subject'] as String?,
      emailSender: row['email_sender'] as String?,
      emailSnippet: row['email_snippet'] as String?,
    );
  }

  final String? databaseId;
  final String gmailMessageId;
  final String title;
  final String? description;
  final String category;
  final DateTime date;
  final double amount;
  final String currency;
  final String source;
  final String? emailSubject;
  final String? emailSender;
  final String? emailSnippet;

  bool get isIncome => amount >= 0;

  String get formattedAmount =>
      formatMoney(amount.abs(), currency: currency, sign: isIncome ? '+' : '-');

  Map<String, dynamic> toDatabase({
    required String userId,
    required String accountId,
  }) {
    return {
      'user_id': userId,
      'account_id': accountId,
      'gmail_message_id': gmailMessageId,
      'merchant_name': title,
      'description': description,
      'amount': amount,
      'currency': currency,
      'category': category,
      'transacted_at': date.toUtc().toIso8601String(),
      'source': source,
      'email_subject': emailSubject,
      'email_sender': emailSender,
      'email_snippet': emailSnippet,
    };
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

String formatMoney(num amount, {String currency = 'MNT', String sign = ''}) {
  final absolute = amount.abs().toDouble();
  final hasFraction = (absolute - absolute.roundToDouble()).abs() > 0.0001;
  final decimals = currency == 'MNT' && !hasFraction ? 0 : 2;
  final fixed = absolute.toStringAsFixed(decimals);
  final pieces = fixed.split('.');
  final digits = pieces.first;
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final value = pieces.length == 2 ? '$grouped.${pieces[1]}' : grouped;
  final symbol = switch (currency.toUpperCase()) {
    'MNT' => '₮',
    'USD' => r'$',
    'EUR' => '€',
    _ => '${currency.toUpperCase()} ',
  };
  return '$sign$symbol$value';
}
