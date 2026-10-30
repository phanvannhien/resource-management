import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repository.dart';
import '../../data/vault.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_nav_bar.dart';
import '../../widgets/ui.dart';
import 'vault_ui.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  String _query = '';
  AccountKind? _kind;

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(vaultProvider) != null;
    final accountsAsync = ref.watch(accountsProvider);
    final data = ref.watch(appDataProvider).value;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: PageTitle(
          'Tài khoản',
          icon: Icons.key_rounded,
          subtitle: unlocked ? 'Kho mật khẩu đang mở' : 'Kho mật khẩu đang khoá',
        ),
        actions: [
          SquareIconButton(
            tooltip: unlocked ? 'Khoá kho' : 'Mở khoá kho',
            icon: unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            onPressed: () =>
                unlocked ? ref.read(vaultProvider.notifier).lock() : requireVault(context, ref),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: SearchBar(
                    hintText: 'Tìm tên, username, khách...',
                    leading: const Icon(Icons.search),
                    constraints: const BoxConstraints(minHeight: 50, maxHeight: 50),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(width: 8),
                FilterBox<AccountKind?>(
                  label: 'Loại tài khoản',
                  placeholder: 'Loại',
                  icon: Icons.category_outlined,
                  value: _kind,
                  isDefault: _kind == null,
                  options: {null: 'Tất cả loại', for (final k in AccountKind.values) k: k.label},
                  onSelected: (k) => setState(() => _kind = k),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: NavBarFab(
        child: FloatingActionButton(
          onPressed: () => context.push('/account/new'),
          child: const Icon(Icons.add),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(accountsProvider.future),
        child: AsyncView(
          value: accountsAsync,
          onRetry: () => ref.invalidate(accountsProvider),
          builder: (accounts) {
            final list = accounts.where((a) {
              if (_kind != null && a.kind != _kind) return false;
              if (_query.isEmpty) return true;
              final fields = [
                a.label,
                a.username,
                a.loginUrl,
                data?.customer(a.customerId)?.name,
                data?.service(a.serviceId)?.name,
                data?.vendor(a.vendorId)?.name,
              ];
              return fields.any((f) => f?.toLowerCase().contains(_query) ?? false);
            }).toList();
            if (list.isEmpty) {
              return ListView(
                children: const [EmptyState('Chưa có tài khoản', icon: Icons.key_off)],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: kNavBarSpace),
              itemCount: list.length,
              itemBuilder: (_, i) => Card(
                child: AccountTile(account: list[i], data: data),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AccountTile extends ConsumerWidget {
  const AccountTile({super.key, required this.account, required this.data});
  final Account account;
  final AppData? data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = account;
    final linked = [
      data?.service(a.serviceId)?.name,
      data?.customer(a.customerId)?.name,
      data?.vendor(a.vendorId)?.name,
    ].whereType<String>().toSet();
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: IconTile(a.kind.icon, color: Theme.of(context).colorScheme.primary, size: 40),
      title: Text(
        a.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        [if (a.username != null) a.username!, ...linked].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: a.passwordEnc == null
          ? null
          : IconButton(
              tooltip: 'Copy mật khẩu',
              icon: const Icon(Icons.password),
              onPressed: () => copyPassword(context, ref, a),
            ),
      onTap: () => showAccountSheet(context, a, data),
    );
  }
}

Future<void> copyPassword(BuildContext context, WidgetRef ref, Account a) async {
  if (a.passwordEnc == null || !await requireVault(context, ref)) return;
  try {
    final pw = await ref.read(vaultProvider.notifier).decrypt(a.passwordEnc!);
    if (context.mounted) {
      await copyText(
        context,
        pw,
        message: 'Đã copy mật khẩu (tự xoá sau 30 giây)',
        clearAfter: const Duration(seconds: 30),
      );
    }
  } catch (_) {
    if (context.mounted) showSnack(context, 'Không giải mã được mật khẩu');
  }
}

Future<void> showAccountSheet(BuildContext context, Account a, AppData? data) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AccountSheet(account: a, data: data),
  );
}

class _AccountSheet extends ConsumerStatefulWidget {
  const _AccountSheet({required this.account, required this.data});
  final Account account;
  final AppData? data;

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  String? _password;

  Future<void> _reveal() async {
    if (!await requireVault(context, ref)) return;
    try {
      final pw = await ref.read(vaultProvider.notifier).decrypt(widget.account.passwordEnc!);
      setState(() => _password = pw);
    } catch (_) {
      if (mounted) showSnack(context, 'Không giải mã được mật khẩu');
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final d = widget.data;
    final service = d?.service(a.serviceId);
    final customer = d?.customer(a.customerId);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(a.kind.icon),
              title: Text(a.label, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(a.kind.label),
              trailing: IconButton(
                tooltip: 'Sửa',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/account/${a.id}/edit');
                },
              ),
            ),
            const Divider(height: 1),
            InfoRow(
              'Đăng nhập',
              a.loginUrl,
              onTap: a.loginUrl == null
                  ? null
                  : () => openUrl(
                      context,
                      a.loginUrl!.contains('://') ? a.loginUrl! : 'https://${a.loginUrl}',
                    ),
            ),
            InfoRow('Username', a.username, copyable: true),
            if (a.passwordEnc != null)
              ListTile(
                dense: true,
                title: const Text('Mật khẩu', style: TextStyle(color: kGrey)),
                subtitle: Text(
                  _password ?? '••••••••',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _password == null ? 'Hiện' : 'Ẩn',
                      icon: Icon(_password == null ? Icons.visibility : Icons.visibility_off),
                      onPressed: _password == null
                          ? _reveal
                          : () => setState(() => _password = null),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy),
                      onPressed: () => copyPassword(context, ref, a),
                    ),
                  ],
                ),
              ),
            InfoRow('Port', a.port?.toString(), copyable: true),
            InfoRow(
              'Dịch vụ',
              service?.name,
              onTap: service == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      context.push('/service/${service.id}');
                    },
            ),
            InfoRow(
              'Khách hàng',
              customer?.name,
              onTap: customer == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      context.push('/customer/${customer.id}');
                    },
            ),
            InfoRow('Nhà cung cấp', d?.vendor(a.vendorId)?.name),
            InfoRow('Ghi chú', a.note),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
