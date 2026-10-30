import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_nav_bar.dart';
import '../../widgets/ui.dart';

enum OwnerFilter { all, mine, customers }

enum StateFilter {
  all('Đang dùng'),
  expiring('Sắp hết hạn'),
  expired('Quá hạn'),
  cancelled('Đã ngừng');

  const StateFilter(this.label);
  final String label;
}

class ServiceFilter {
  const ServiceFilter({
    this.type,
    this.owner = OwnerFilter.all,
    this.state = StateFilter.all,
    this.query = '',
  });

  final ServiceType? type;
  final OwnerFilter owner;
  final StateFilter state;
  final String query;

  ServiceFilter copyWith({
    ServiceType? Function()? type,
    OwnerFilter? owner,
    StateFilter? state,
    String? query,
  }) => ServiceFilter(
    type: type != null ? type() : this.type,
    owner: owner ?? this.owner,
    state: state ?? this.state,
    query: query ?? this.query,
  );

  bool matches(Service s, AppData data) {
    if (type != null && s.type != type) return false;
    if (owner == OwnerFilter.mine && !s.isMine) return false;
    if (owner == OwnerFilter.customers && s.isMine) return false;
    final ok = switch (state) {
      StateFilter.all => !s.cancelled,
      StateFilter.expiring => s.state == ExpiryState.expiring,
      StateFilter.expired => s.state == ExpiryState.expired,
      StateFilter.cancelled => s.cancelled,
    };
    if (!ok) return false;
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return s.name.toLowerCase().contains(q) ||
        data.ownerName(s).toLowerCase().contains(q) ||
        (s.ip?.contains(q) ?? false);
  }
}

class ServiceFilterController extends Notifier<ServiceFilter> {
  @override
  ServiceFilter build() => const ServiceFilter();

  void set(ServiceFilter f) => state = f;
}

final serviceFilterProvider = NotifierProvider<ServiceFilterController, ServiceFilter>(
  ServiceFilterController.new,
);

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final type = await showModalBottomSheet<ServiceType>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in ServiceType.values)
              ListTile(
                leading: Icon(t.icon),
                title: Text('Thêm ${t.label}'),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (type != null && context.mounted) context.push('/service/new?type=${type.db}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(serviceFilterProvider);
    final ctrl = ref.read(serviceFilterProvider.notifier);

    final filtered =
        filter.type != null || filter.state != StateFilter.all || filter.owner != OwnerFilter.all;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: const PageTitle(
          'Dịch vụ',
          icon: Icons.dns_rounded,
          subtitle: 'Domain · Hosting · VPS',
        ),
        actions: [
          SquareIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Cài đặt',
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(118),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchBar(
                  hintText: 'Tìm tên, khách, IP...',
                  leading: const Icon(Icons.search, size: 20),
                  elevation: const WidgetStatePropertyAll(0),
                  constraints: const BoxConstraints(minHeight: 50, maxHeight: 50),
                  onChanged: (v) => ctrl.set(filter.copyWith(query: v.trim())),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilterBox<ServiceType?>(
                        label: 'Loại dịch vụ',
                        placeholder: 'Loại',
                        icon: Icons.category_outlined,
                        expanded: true,
                        value: filter.type,
                        options: {
                          null: 'Tất cả loại',
                          for (final t in ServiceType.values) t: t.label,
                        },
                        isDefault: filter.type == null,
                        onSelected: (v) => ctrl.set(filter.copyWith(type: () => v)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: FilterBox<StateFilter>(
                        label: 'Trạng thái',
                        icon: Icons.schedule_rounded,
                        expanded: true,
                        value: filter.state,
                        options: {for (final st in StateFilter.values) st: st.label},
                        isDefault: filter.state == StateFilter.all,
                        onSelected: (v) => ctrl.set(filter.copyWith(state: v)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: FilterBox<OwnerFilter>(
                        label: 'Chủ sở hữu',
                        placeholder: 'Chủ',
                        icon: Icons.person_outline_rounded,
                        expanded: true,
                        value: filter.owner,
                        options: const {
                          OwnerFilter.all: 'Tất cả chủ',
                          OwnerFilter.mine: 'Của tôi',
                          OwnerFilter.customers: 'Của khách',
                        },
                        isDefault: filter.owner == OwnerFilter.all,
                        onSelected: (v) => ctrl.set(filter.copyWith(owner: v)),
                      ),
                    ),
                    if (filtered)
                      IconButton(
                        tooltip: 'Bỏ lọc',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => ctrl.set(ServiceFilter(query: filter.query)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: NavBarFab(
        child: FloatingActionButton(onPressed: () => _add(context), child: const Icon(Icons.add)),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(appDataProvider.future),
        child: AsyncView(
          value: ref.watch(appDataProvider),
          onRetry: () => ref.invalidate(appDataProvider),
          builder: (data) {
            final list = data.services.where((s) => filter.matches(s, data)).toList();
            if (list.isEmpty) {
              return ListView(children: const [EmptyState('Không có dịch vụ nào')]);
            }
            return ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: kNavBarSpace),
              itemCount: list.length,
              itemBuilder: (_, i) => Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ServiceTile(service: list[i], data: data, dense: true),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
