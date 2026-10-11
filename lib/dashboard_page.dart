import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bank_transaction.dart';
import 'gmail_service.dart';
import 'login_page.dart';
import 'theme.dart';
import 'transaction_repository.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  static const routeName = '/dashboard';

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _repository = TransactionRepository();
  bool _balanceVisible = true;
  bool _syncing = false;
  bool _loading = true;
  String? _loadError;
  DashboardSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDashboard());
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final snapshot = await _repository.loadDashboard();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncInbox() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      if (!GmailService.instance.isConnected) {
        await GmailService.instance.connect();
      }

      final lastSync = _snapshot?.lastSyncedAt;
      final overlapSeconds = lastSync == null
          ? null
          : lastSync.toUtc().millisecondsSinceEpoch ~/ 1000 - 86400;
      final result = await GmailService.instance.syncBankTransactions(
        query: overlapSeconds == null
            ? 'newer_than:90d {transaction payment purchase deposit transfer debit credit balance гүйлгээ үлдэгдэл}'
            : 'after:$overlapSeconds {transaction payment purchase deposit transfer debit credit balance гүйлгээ үлдэгдэл}',
      );
      await _repository.saveGmailSync(result);
      final refreshed = await _repository.loadDashboard();
      if (!mounted) return;
      setState(() => _snapshot = refreshed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${result.transactions.length} transactions from ${result.messagesScanned} bank emails.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gmail sync failed: $error')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _logout() async {
    await Future.wait([
      GmailService.instance.disconnect(),
      Supabase.instance.client.auth.signOut(),
    ]);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(LoginPage.routeName, (_) => false);
  }

  static String _friendlyError(Object error) {
    if (error is PostgrestException) return error.message;
    if (error is AuthException) return error.message;
    return 'Could not load your transactions. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 980;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (desktop) _DesktopRail(onLogout: () => unawaited(_logout())),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 38 : 20,
                          22,
                          desktop ? 38 : 20,
                          40,
                        ),
                        sliver: SliverList.list(
                          children: [
                            _DashboardHeader(
                              syncing: _syncing,
                              onSync: _syncInbox,
                              onLogout: () => unawaited(_logout()),
                              greetingName:
                                  Supabase
                                      .instance
                                      .client
                                      .auth
                                      .currentUser
                                      ?.userMetadata?['display_name']
                                      ?.toString()
                                      .split(' ')
                                      .first ??
                                  'there',
                              gmailEmail: GmailService.instance.account?.email,
                            ),
                            const SizedBox(height: 28),
                            if (_loading && _snapshot == null)
                              const _DashboardLoading()
                            else if (_loadError != null && _snapshot == null)
                              _DashboardError(
                                message: _loadError!,
                                onRetry: _loadDashboard,
                              )
                            else ...[
                              _DashboardGrid(
                                desktop: desktop,
                                balanceVisible: _balanceVisible,
                                snapshot: _snapshot!,
                                onToggleBalance: () => setState(
                                  () => _balanceVisible = !_balanceVisible,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _ActivityLayout(
                                desktop: desktop,
                                snapshot: _snapshot!,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 980
          ? NavigationBar(
              selectedIndex: 0,
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Overview',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  label: 'Activity',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Settings',
                ),
              ],
            )
          : null,
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 245,
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _LogoBox(),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Mailance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 44),
          const _RailItem(
            icon: Icons.grid_view_rounded,
            label: 'Overview',
            selected: true,
          ),
          const _RailItem(
            icon: Icons.receipt_long_outlined,
            label: 'Transactions',
          ),
          const _RailItem(
            icon: Icons.pie_chart_outline_rounded,
            label: 'Insights',
          ),
          const _RailItem(
            icon: Icons.account_balance_outlined,
            label: 'Accounts',
          ),
          const Spacer(),
          const _RailItem(icon: Icons.settings_outlined, label: 'Settings'),
          _RailItem(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

class _LogoBox extends StatelessWidget {
  const _LogoBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Image.asset(
        'assets/mailance_logo.png',
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap ?? () {},
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : Colors.white60,
                  size: 21,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.syncing,
    required this.onSync,
    required this.onLogout,
    required this.greetingName,
    required this.gmailEmail,
  });

  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback onLogout;
  final String greetingName;
  final String? gmailEmail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good morning, $greetingName',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                gmailEmail ?? 'Here’s what your money is doing today.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width > 570)
          OutlinedButton.icon(
            key: const Key('syncButton'),
            onPressed: syncing ? null : onSync,
            icon: syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 19),
            label: Text(syncing ? 'Syncing…' : 'Sync inbox'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.line),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          )
        else
          IconButton.filledTonal(
            tooltip: 'Connect Gmail and sync',
            onPressed: syncing ? null : onSync,
            icon: syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        const SizedBox(width: 12),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'logout') onLogout();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'profile', child: Text('Profile')),
            PopupMenuItem(value: 'logout', child: Text('Sign out')),
          ],
          child: const CircleAvatar(
            radius: 23,
            backgroundColor: AppColors.mint,
            child: Text(
              'AK',
              style: TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardGrid extends StatelessWidget {
  const _DashboardGrid({
    required this.desktop,
    required this.balanceVisible,
    required this.snapshot,
    required this.onToggleBalance,
  });

  final bool desktop;
  final bool balanceVisible;
  final DashboardSnapshot snapshot;
  final VoidCallback onToggleBalance;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _BalanceCard(
        balanceVisible: balanceVisible,
        balance: snapshot.currentBalance == null
            ? 'Not available'
            : formatMoney(
                snapshot.currentBalance!,
                currency: snapshot.balanceCurrency,
              ),
        onToggle: onToggleBalance,
      ),
      _TodayCard(
        amount: formatMoney(
          snapshot.todaySpent,
          currency: snapshot.balanceCurrency,
          sign: snapshot.todaySpent == 0 ? '' : '-',
        ),
        transactionCount: snapshot.todayTransactionCount,
      ),
      _MonthCard(
        amount: formatMoney(
          snapshot.monthSpent,
          currency: snapshot.balanceCurrency,
        ),
        transactionCount: snapshot.monthTransactionCount,
      ),
    ];

    if (desktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 10, child: cards[0]),
          const SizedBox(width: 16),
          Expanded(flex: 7, child: cards[1]),
          const SizedBox(width: 16),
          Expanded(flex: 7, child: cards[2]),
        ],
      );
    }

    return Column(
      children: [
        cards[0],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[1]),
            if (MediaQuery.sizeOf(context).width >= 610) ...[
              const SizedBox(width: 14),
              Expanded(child: cards[2]),
            ],
          ],
        ),
        if (MediaQuery.sizeOf(context).width < 610) ...[
          const SizedBox(height: 14),
          cards[2],
        ],
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.color = AppColors.surface});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color == AppColors.surface ? AppColors.line : color,
        ),
      ),
      child: child,
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balanceVisible,
    required this.balance,
    required this.onToggle,
  });

  final bool balanceVisible;
  final String balance;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      color: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CURRENT BALANCE',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: balanceVisible ? 'Hide balance' : 'Show balance',
                onPressed: onToggle,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  balanceVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            balanceVisible ? balance : '••••••••',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: Color(0xFFB8F0D8),
                size: 19,
              ),
              const SizedBox(width: 7),
              Text(
                'Stored securely for your account',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.amount, required this.transactionCount});

  final String amount;
  final int transactionCount;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(icon: Icons.today_outlined, label: 'TODAY'),
          const SizedBox(height: 20),
          Text(
            amount,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Across $transactionCount transactions',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          const _TinyProgress(value: 0.42, color: AppColors.coral),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.amount, required this.transactionCount});

  final String amount;
  final int transactionCount;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(
            icon: Icons.calendar_month_outlined,
            label: 'THIS MONTH',
          ),
          const SizedBox(height: 20),
          Text(
            amount,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$transactionCount recorded transactions',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          const _TinyProgress(value: 1, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
          ),
        ),
      ],
    );
  }
}

class _TinyProgress extends StatelessWidget {
  const _TinyProgress({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 6,
        color: color,
        backgroundColor: AppColors.line,
      ),
    );
  }
}

class _ActivityLayout extends StatelessWidget {
  const _ActivityLayout({required this.desktop, required this.snapshot});

  final bool desktop;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (desktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 15,
            child: _TransactionsPanel(transactions: snapshot.transactions),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 7,
            child: _SpendingPanel(
              categorySpending: snapshot.categorySpending,
              monthSpent: snapshot.monthSpent,
              currency: snapshot.balanceCurrency,
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _TransactionsPanel(transactions: snapshot.transactions),
        const SizedBox(height: 18),
        _SpendingPanel(
          categorySpending: snapshot.categorySpending,
          monthSpent: snapshot.monthSpent,
          currency: snapshot.balanceCurrency,
        ),
      ],
    );
  }
}

class _TransactionsPanel extends StatelessWidget {
  const _TransactionsPanel({required this.transactions});

  final List<BankTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final displayedTransactions = transactions.take(8).toList();
    return _CardShell(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Today’s transactions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                '${transactions.length} loaded',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (displayedTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    color: AppColors.muted,
                    size: 32,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No saved transactions yet. Connect Gmail and sync your inbox.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            )
          else
            ...displayedTransactions.indexed.map(
              (entry) => _TransactionRow(
                transaction: entry.$2,
                showDivider: entry.$1 != displayedTransactions.length - 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _TransactionVisual {
  const _TransactionVisual(this.icon, this.background, this.foreground);

  factory _TransactionVisual.forCategory(String category) {
    final (icon, background, foreground) = switch (category) {
      'Income' => (
        Icons.south_west_rounded,
        const Color(0xFFDDF3E8),
        AppColors.primary,
      ),
      'Dining' => (
        Icons.local_cafe_outlined,
        const Color(0xFFFFEEE0),
        const Color(0xFFA25B2C),
      ),
      'Groceries' => (
        Icons.shopping_basket_outlined,
        const Color(0xFFE6F2E9),
        const Color(0xFF2E7255),
      ),
      'Transport' => (
        Icons.directions_bus_outlined,
        const Color(0xFFE7EBF7),
        const Color(0xFF526A9B),
      ),
      _ => (
        Icons.account_balance_wallet_outlined,
        const Color(0xFFE9ECE8),
        AppColors.muted,
      ),
    };
    return _TransactionVisual(icon, background, foreground);
  }

  final IconData icon;
  final Color background;
  final Color foreground;
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, required this.showDivider});

  final BankTransaction transaction;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final visual = _TransactionVisual.forCategory(transaction.category);
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showTransactionDetails(context, transaction),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: visual.background,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(visual.icon, color: visual.foreground, size: 21),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${transaction.category}  •  ${_formatDateTime(transaction.date)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  transaction.formattedAmount,
                  style: TextStyle(
                    color: transaction.isIncome
                        ? AppColors.primary
                        : AppColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class _SpendingPanel extends StatelessWidget {
  const _SpendingPanel({
    required this.categorySpending,
    required this.monthSpent,
    required this.currency,
  });

  final Map<String, double> categorySpending;
  final double monthSpent;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spending this month',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '${formatMoney(monthSpent, currency: currency)} total',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 25),
          if (categorySpending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Category totals will appear after your first sync.',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            ...categorySpending.entries.take(5).toList().indexed.map((entry) {
              const colors = [
                AppColors.primary,
                Color(0xFFD8A048),
                Color(0xFF6D7EB5),
                AppColors.coral,
                Color(0xFF7D6AA5),
              ];
              final item = entry.$2;
              return _SpendingBar(
                label: item.key,
                amount: formatMoney(item.value, currency: currency),
                value: monthSpent == 0
                    ? 0
                    : (item.value / monthSpent).clamp(0, 1),
                color: colors[entry.$1 % colors.length],
              );
            }),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Totals include saved expense transactions from this month.',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendingBar extends StatelessWidget {
  const _SpendingBar({
    required this.label,
    required this.amount,
    required this.value,
    required this.color,
  });

  final String label;
  final String amount;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 19),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                amount,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TinyProgress(value: value, color: color),
        ],
      ),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const _CardShell(
      child: SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 36,
            color: AppColors.coral,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final date =
      '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date  $time';
}

void _showTransactionDetails(
  BuildContext context,
  BankTransaction transaction,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Transaction details',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 22),
            Text(
              transaction.formattedAmount,
              style: TextStyle(
                color: transaction.isIncome ? AppColors.primary : AppColors.ink,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            _DetailRow(label: 'Merchant / subject', value: transaction.title),
            _DetailRow(label: 'Category', value: transaction.category),
            _DetailRow(
              label: 'Date and time',
              value: _formatDateTime(transaction.date),
            ),
            _DetailRow(label: 'Currency', value: transaction.currency),
            _DetailRow(
              label: 'Source',
              value: transaction.source.toUpperCase(),
            ),
            if (transaction.description?.isNotEmpty ?? false)
              _DetailRow(label: 'Description', value: transaction.description!),
            if (transaction.emailSender?.isNotEmpty ?? false)
              _DetailRow(
                label: 'Email sender',
                value: transaction.emailSender!,
              ),
            if (transaction.emailSnippet?.isNotEmpty ?? false)
              _DetailRow(
                label: 'Email preview',
                value: transaction.emailSnippet!,
              ),
            _DetailRow(
              label: 'Import reference',
              value: transaction.gmailMessageId,
              monospace: true,
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            value,
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
