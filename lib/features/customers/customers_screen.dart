import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_nav_bar.dart';
import '../../widgets/ui.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: Consumer(
          builder: (_, ref, _) {
            final n = ref.watch(appDataProvider).value?.customers.where((c) => c.isActive).length;
            return PageTitle(
              'Khách hàng',
              icon: Icons.people_alt_rounded,
              subtitle: n == null ? null : '$n khách đang sử dụng dịch vụ',
            );
          },
        ),
        actions: [
          SquareIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Cài đặt',
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SearchBar(
              hintText: 'Tìm tên, SĐT, công ty...',
              leading: const Icon(Icons.search),
              constraints: const BoxConstraints(minHeight: 50, maxHeight: 50),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              trailing: [
                IconButton(
                  tooltip: _showInactive ? 'Ẩn khách đã ngừng' : 'Hiện khách đã ngừng',
                  icon: Icon(_showInactive ? Icons.visibility : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _showInactive = !_showInactive),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: NavBarFab(
        child: FloatingActionButton(
          onPressed: () => context.push('/customer/new'),
          child: const Icon(Icons.person_add_alt),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(appDataProvider.future),
        child: AsyncView(
          value: ref.watch(appDataProvider),
          onRetry: () => ref.invalidate(appDataProvider),
          builder: (data) {
            final list = data.customers.where((c) {
              if (!_showInactive && !c.isActive) return false;
              if (_query.isEmpty) return true;
              return [
                c.name,
                c.phone,
                c.company,
                c.email,
                c.zalo,
              ].any((f) => f?.toLowerCase().contains(_query) ?? false);
            }).toList();
            if (list.isEmpty) {
              return ListView(children: const [EmptyState('Chưa có khách hàng')]);
            }
            return ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: kNavBarSpace),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                final services = data.servicesOf(c.id!).where((s) => !s.cancelled).toList();
                final due = services.where((s) => s.needsRenewal).length;
                final color = due > 0 ? kOrange : Theme.of(context).colorScheme.primary;
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase(),
                        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    ),
                    title: Text(
                      c.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        decoration: c.isActive ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (c.phone != null) c.phone!,
                        if (c.company != null) c.company!,
                        '${services.length} dịch vụ',
                      ].join(' · '),
                    ),
                    trailing: due > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: kOrange.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$due cần gia hạn',
                              style: const TextStyle(
                                color: kOrange,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => context.push('/customer/${c.id}'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
