import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart';

import 'bank_transaction.dart';

const gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';

/// This OAuth client ID is public configuration, not a client secret. Override it
/// for another Google Cloud project with `--dart-define=GOOGLE_WEB_CLIENT_ID=...`.
const googleOAuthWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue:
      '1034954657947-rto256igsjd879sd027vac1438u6m211.apps.googleusercontent.com',
);

class GmailSyncResult {
  const GmailSyncResult({
    required this.transactions,
    required this.messagesScanned,
    required this.searchQuery,
    this.currentBalance,
    this.balanceCurrency = 'MNT',
  });

  final List<BankTransaction> transactions;
  final int messagesScanned;
  final String searchQuery;
  final double? currentBalance;
  final String balanceCurrency;
}

class GmailService {
  GmailService._();

  static final instance = GmailService._();

  static const scopes = <String>[gmailReadonlyScope];

  final _signIn = GoogleSignIn.instance;
  GmailApi? _gmailApi;
  bool _initialized = false;

  GoogleSignInAccount? account;

  bool get isConnected => account != null && _gmailApi != null;

  Future<GoogleSignInAccount> connect() async {
    if (googleOAuthWebClientId.isEmpty) {
      throw const GmailSetupException(
        'The Google OAuth client ID has not been configured yet.',
      );
    }

    await _ensureInitialized();
    if (!_signIn.supportsAuthenticate()) {
      throw const GmailSetupException(
        'This sign-in flow is currently configured for Android and iOS.',
      );
    }

    final signedInAccount = await _signIn.authenticate(scopeHint: scopes);
    var authorization = await signedInAccount.authorizationClient
        .authorizationForScopes(scopes);
    authorization ??= await signedInAccount.authorizationClient.authorizeScopes(
      scopes,
    );

    _gmailApi = GmailApi(authorization.authClient(scopes: scopes));
    account = signedInAccount;
    return signedInAccount;
  }

  Future<void> disconnect() async {
    final shouldDisconnect = _initialized && account != null;
    _gmailApi = null;
    account = null;
    if (shouldDisconnect) await _signIn.disconnect();
  }

  Future<GmailSyncResult> syncBankTransactions({
    String query =
        'newer_than:90d {transaction payment purchase deposit transfer debit credit balance гүйлгээ үлдэгдэл}',
  }) async {
    final api = _gmailApi;
    if (api == null) {
      throw const GmailSetupException(
        'Connect a Gmail account before syncing.',
      );
    }

    final response = await api.users.messages.list(
      'me',
      q: query,
      maxResults: 75,
    );
    final messageRefs = response.messages ?? const <Message>[];
    final parsedMessages = <_ParsedBankMessage>[];

    // Gmail's API is network-bound. Small concurrent batches are substantially
    // faster than fetching every message sequentially without flooding the API.
    for (var start = 0; start < messageRefs.length; start += 10) {
      final end = (start + 10).clamp(0, messageRefs.length);
      final batch = messageRefs.sublist(start, end);
      final parsedBatch = await Future.wait(
        batch.map((messageRef) async {
          final id = messageRef.id;
          if (id == null) {
            return _ParsedBankMessage(
              observedAt: DateTime.fromMillisecondsSinceEpoch(0),
            );
          }
          final message = await api.users.messages.get(
            'me',
            id,
            format: 'full',
          );
          return _parseMessage(message);
        }),
      );
      parsedMessages.addAll(parsedBatch);
    }

    final transactions =
        parsedMessages
            .map((parsed) => parsed.transaction)
            .whereType<BankTransaction>()
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final balances =
        parsedMessages.where((parsed) => parsed.balance != null).toList()
          ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    final latestBalance = balances.isEmpty ? null : balances.first;

    return GmailSyncResult(
      transactions: transactions,
      messagesScanned: messageRefs.length,
      searchQuery: query,
      currentBalance: latestBalance?.balance,
      balanceCurrency: latestBalance?.balanceCurrency ?? 'MNT',
    );
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _signIn.initialize(
      clientId: kIsWeb ? googleOAuthWebClientId : null,
      serverClientId: kIsWeb ? null : googleOAuthWebClientId,
    );
    _initialized = true;
  }

  _ParsedBankMessage _parseMessage(Message message) {
    final subject = _header(message, 'Subject');
    final sender = _header(message, 'From');
    final body = _messageText(message.payload);
    final snippet = message.snippet ?? '';
    final searchable = '$subject\n$sender\n$body\n$snippet'
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
    final timestamp = int.tryParse(message.internalDate ?? '');
    final date = timestamp == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
    final balance = _findBalance(searchable);
    final money = _findTransactionMoney(searchable);

    if (money == null) {
      return _ParsedBankMessage(
        balance: balance?.$1,
        balanceCurrency: balance?.$2 ?? 'MNT',
        observedAt: date,
      );
    }

    final lower = searchable.toLowerCase();
    final income = _isIncome(lower);
    final transaction = BankTransaction(
      gmailMessageId: message.id ?? '${date.microsecondsSinceEpoch}',
      title: subject.isEmpty ? _cleanSender(sender) : subject.trim(),
      description: _cleanSender(sender),
      category: _categoryFor(lower),
      date: date,
      amount: income ? money.$1.abs() : -money.$1.abs(),
      currency: money.$2,
      emailSubject: subject.isEmpty ? null : subject,
      emailSender: sender.isEmpty ? null : sender,
      emailSnippet: snippet.isEmpty ? null : snippet,
    );

    return _ParsedBankMessage(
      transaction: transaction,
      balance: balance?.$1,
      balanceCurrency: balance?.$2 ?? 'MNT',
      observedAt: date,
    );
  }

  static (double, String)? _findTransactionMoney(String text) {
    RegExpMatch? bestMatch;
    var bestScore = -1000;

    for (final match in _moneyPattern.allMatches(text)) {
      final start = (match.start - 55).clamp(0, text.length);
      final end = (match.end + 35).clamp(0, text.length);
      final context = text.substring(start, end).toLowerCase();
      final prefixStart = (match.start - 32).clamp(0, text.length);
      final prefix = text.substring(prefixStart, match.start).toLowerCase();
      var score = 0;
      if (_transactionWords.any(context.contains)) score += 5;
      if (_amountWords.any(context.contains)) score += 4;
      if (_balanceWords.any(prefix.contains)) score -= 10;
      if (match.group(1) != null || match.group(4) != null) score += 1;
      if (score > bestScore) {
        bestScore = score;
        bestMatch = match;
      }
    }
    if (bestMatch == null || bestScore < 0) return null;
    final raw = bestMatch.group(2) ?? bestMatch.group(3);
    final amount = _parseMoney(raw);
    if (amount == null) return null;
    return (amount, _currencyFrom(bestMatch.group(0) ?? ''));
  }

  static (double, String)? _findBalance(String text) {
    for (final keyword in _balanceKeywordPattern.allMatches(text)) {
      final end = (keyword.end + 90).clamp(0, text.length);
      final match = _moneyPattern.firstMatch(
        text.substring(keyword.start, end),
      );
      if (match == null) continue;
      final amount = _parseMoney(match.group(2) ?? match.group(3));
      if (amount != null) {
        return (amount, _currencyFrom(match.group(0) ?? ''));
      }
    }
    return null;
  }

  static String _header(Message message, String name) {
    for (final header
        in message.payload?.headers ?? const <MessagePartHeader>[]) {
      if (header.name?.toLowerCase() == name.toLowerCase()) {
        return header.value ?? '';
      }
    }
    return '';
  }

  static String _messageText(MessagePart? part) {
    if (part == null) return '';
    final data = part.body?.data;
    if (data != null && data.isNotEmpty) {
      try {
        final normalized = base64Url.normalize(data);
        final decoded = utf8.decode(
          base64Url.decode(normalized),
          allowMalformed: true,
        );
        if (part.mimeType == 'text/html') {
          return decoded.replaceAll(RegExp('<[^>]*>'), ' ');
        }
        return decoded;
      } on FormatException {
        // Fall through to multipart children when the body is not decodable.
      }
    }
    return (part.parts ?? const <MessagePart>[])
        .map(_messageText)
        .where((value) => value.isNotEmpty)
        .join('\n');
  }

  static double? _parseMoney(String? raw) {
    if (raw == null) return null;
    var cleaned = raw.replaceAll(RegExp(r'[^0-9,.+-]'), '');
    if (cleaned.isEmpty) return null;
    final comma = cleaned.lastIndexOf(',');
    final dot = cleaned.lastIndexOf('.');
    final separator = comma > dot ? comma : dot;
    if (separator >= 0) {
      final fractionalDigits = cleaned.length - separator - 1;
      if (fractionalDigits == 2) {
        final whole = cleaned
            .substring(0, separator)
            .replaceAll(RegExp(r'[,.]'), '');
        final fraction = cleaned.substring(separator + 1);
        cleaned = '$whole.$fraction';
      } else {
        cleaned = cleaned.replaceAll(RegExp(r'[,.]'), '');
      }
    }
    return double.tryParse(cleaned);
  }

  static String _currencyFrom(String raw) {
    final upper = raw.toUpperCase();
    if (upper.contains('MNT') ||
        raw.contains('₮') ||
        upper.contains('ТӨГРӨГ')) {
      return 'MNT';
    }
    if (upper.contains('EUR') || raw.contains('€')) return 'EUR';
    if (upper.contains('USD') || raw.contains(r'$')) return 'USD';
    return 'MNT';
  }

  static String _cleanSender(String sender) {
    final angle = sender.indexOf('<');
    return (angle == -1 ? sender : sender.substring(0, angle))
        .replaceAll('"', '')
        .trim();
  }

  static String _categoryFor(String text) {
    if (_incomeWords.any(text.contains)) return 'Income';
    if (RegExp(
      r'coffee|cafe|restaurant|food|dining|кофе|ресторан|хоол',
    ).hasMatch(text)) {
      return 'Dining';
    }
    if (RegExp(r'market|grocery|supermarket|дэлгүүр|хүнс').hasMatch(text)) {
      return 'Groceries';
    }
    if (RegExp(
      r'taxi|uber|bus|metro|fuel|transport|такси|шатахуун|автобус',
    ).hasMatch(text)) {
      return 'Transport';
    }
    if (RegExp(r'rent|mortgage|utility|electric|internet').hasMatch(text)) {
      return 'Bills';
    }
    return 'Bank activity';
  }

  static bool _isIncome(String text) {
    final income = _incomeWords.any(text.contains);
    final expense = _expenseWords.any(text.contains);
    return income && !expense;
  }

  static final _moneyPattern = RegExp(
    r'(?:(USD|MNT|EUR|\$|₮|€|төгрөг)\s*([+-]?[0-9][0-9,.\s]*[0-9]|[+-]?[0-9]+)|([+-]?[0-9][0-9,.\s]*[0-9]|[+-]?[0-9]+)\s*(USD|MNT|EUR|₮|€|төгрөг))',
    caseSensitive: false,
  );
  static final _balanceKeywordPattern = RegExp(
    r'available\s+balance|current\s+balance|balance|үлдэгдэл',
    caseSensitive: false,
  );
  static const _balanceWords = <String>[
    'available balance',
    'current balance',
    'balance',
    'үлдэгдэл',
  ];
  static const _transactionWords = <String>[
    'transaction',
    'payment',
    'purchase',
    'transfer',
    'debit',
    'credit',
    'deposit',
    'гүйлгээ',
    'зарлага',
    'орлого',
  ];
  static const _amountWords = <String>['amount', 'total', 'дүн', 'мөнгөн дүн'];
  static const _incomeWords = <String>[
    'credited',
    'credit transaction',
    'deposit',
    'received',
    'salary',
    'income',
    'орлого',
    'дансанд орсон',
  ];
  static const _expenseWords = <String>[
    'debited',
    'debit transaction',
    'purchase',
    'payment',
    'spent',
    'зарлага',
    'хасагдлаа',
  ];
}

class GmailSetupException implements Exception {
  const GmailSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ParsedBankMessage {
  const _ParsedBankMessage({
    this.transaction,
    this.balance,
    this.balanceCurrency = 'MNT',
    required this.observedAt,
  });

  final BankTransaction? transaction;
  final double? balance;
  final String balanceCurrency;
  final DateTime observedAt;
}
