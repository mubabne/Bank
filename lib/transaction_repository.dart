import 'package:supabase_flutter/supabase_flutter.dart';

import 'bank_transaction.dart';
import 'gmail_service.dart';

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.transactions,
    required this.categorySpending,
    required this.todaySpent,
    required this.todayTransactionCount,
    required this.monthSpent,
    required this.monthTransactionCount,
    this.currentBalance,
    this.balanceCurrency = 'MNT',
    this.lastSyncedAt,
  });

  final List<BankTransaction> transactions;
  final Map<String, double> categorySpending;
  final double? currentBalance;
  final String balanceCurrency;
  final double todaySpent;
  final int todayTransactionCount;
  final double monthSpent;
  final int monthTransactionCount;
  final DateTime? lastSyncedAt;
}

class TransactionRepository {
  TransactionRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  User get _requiredUser {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in before accessing transactions.');
    }
    return user;
  }

  Future<DashboardSnapshot> loadDashboard() async {
    _requiredUser;
    final results = await Future.wait<dynamic>([
      _client
          .from('transactions')
          .select(
            'id,gmail_message_id,merchant_name,description,amount,currency,'
            'category,transacted_at,source,email_subject,email_sender,email_snippet',
          )
          .order('transacted_at', ascending: false)
          .limit(50),
      _client.rpc('get_dashboard_summary'),
      _client.rpc('get_monthly_category_spending'),
    ]);

    final transactionRows = (results[0] as List).cast<Map<String, dynamic>>();
    final summaryRows = (results[1] as List).cast<Map<String, dynamic>>();
    final categoryRows = (results[2] as List).cast<Map<String, dynamic>>();
    final summary = summaryRows.isEmpty
        ? const <String, dynamic>{}
        : summaryRows.first;

    return DashboardSnapshot(
      transactions: transactionRows.map(BankTransaction.fromDatabase).toList(),
      categorySpending: {
        for (final row in categoryRows)
          row['category'] as String? ?? 'Other': _asDouble(row['total']),
      },
      currentBalance: summary['current_balance'] == null
          ? null
          : _asDouble(summary['current_balance']),
      balanceCurrency: summary['balance_currency'] as String? ?? 'MNT',
      todaySpent: _asDouble(summary['today_spent']),
      todayTransactionCount: _asInt(summary['today_transaction_count']),
      monthSpent: _asDouble(summary['month_spent']),
      monthTransactionCount: _asInt(summary['month_transaction_count']),
      lastSyncedAt: _asDate(summary['last_synced_at']),
    );
  }

  Future<void> saveGmailSync(GmailSyncResult result) async {
    final user = _requiredUser;
    final now = DateTime.now().toUtc();
    final gmailEmail = GmailService.instance.account?.email;

    try {
      final account = await _client
          .from('accounts')
          .upsert({
            'user_id': user.id,
            'name': 'Gmail imports',
            'bank_name': gmailEmail,
            'currency': result.balanceCurrency,
            if (result.currentBalance != null)
              'current_balance': result.currentBalance,
            'last_synced_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          }, onConflict: 'user_id,name')
          .select('id')
          .single();

      if (result.transactions.isNotEmpty) {
        final accountId = account['id'] as String;
        await _client
            .from('transactions')
            .upsert(
              result.transactions
                  .map(
                    (transaction) => transaction.toDatabase(
                      userId: user.id,
                      accountId: accountId,
                    ),
                  )
                  .toList(),
              onConflict: 'user_id,gmail_message_id',
            );
      }

      await _client.from('sync_state').upsert({
        'user_id': user.id,
        'gmail_email': gmailEmail,
        'search_query': result.searchQuery,
        'last_sync_at': now.toIso8601String(),
        'sync_status': 'success',
        'last_error': null,
        'messages_scanned': result.messagesScanned,
        'updated_at': now.toIso8601String(),
      });
    } catch (error) {
      await _saveSyncError(user.id, gmailEmail, error);
      rethrow;
    }
  }

  Future<void> _saveSyncError(
    String userId,
    String? gmailEmail,
    Object error,
  ) async {
    try {
      await _client.from('sync_state').upsert({
        'user_id': userId,
        'gmail_email': gmailEmail,
        'sync_status': 'error',
        'last_error': error.toString().substring(
          0,
          error.toString().length > 500 ? 500 : error.toString().length,
        ),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Preserve the original persistence error.
    }
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
