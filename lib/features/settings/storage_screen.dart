import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/local_repository.dart';
import '../../data/repository.dart';
import '../../data/storage_config.dart';
import '../../data/storage_switch.dart';
import '../../data/sync.dart';
import '../../widgets/common.dart';
import '../../widgets/form_kit.dart';
import '../../widgets/glass_nav_bar.dart';
import '../../widgets/ui.dart';
import 'backup_actions.dart';

/// Cài đặt → Lưu trữ dữ liệu: xem/đổi nơi lưu, đồng bộ WebDAV, sao lưu/khôi phục file.
class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  late final _davUrl = TextEditingController();
  late final _davUser = TextEditingController();
  late final _davPass = TextEditingController();
  bool _davOn = false;
  bool _obscure = true;
  bool _testing = false;
  bool _switching = false;
  String? _davTestResult;
  ({String path, int size, String updatedAt})? _fileInfo;

  @override
  void initState() {
    super.initState();
    final dav = ref.read(storageConfigProvider).webdav;
    _davOn = dav.enabled;
    _davUrl.text = dav.url;
    _davUser.text = dav.username;
    _davPass.text = dav.password;
    _loadFileInfo();
  }

  @override
  void dispose() {
    _davUrl.dispose();
    _davUser.dispose();
    _davPass.dispose();
    super.dispose();
  }

  Future<void> _loadFileInfo() async {
    final repo = ref.read(repositoryProvider);
    if (repo is! LocalRepository) return;
    await repo.ensureLoaded();
    final f = await repo.file();
    final size = await f.exists() ? await f.length() : 0;
    if (mounted) setState(() => _fileInfo = (path: f.path, size: size, updatedAt: repo.updatedAt));
  }

  WebDavConfig get _davForm => WebDavConfig(
        enabled: _davOn,
        url: _davUrl.text.trim(),
        username: _davUser.text.trim(),
        password: _davPass.text,
      );

  Future<void> _saveDav({bool? enabled}) async {
    if (enabled != null) setState(() => _davOn = enabled);
    await ref.read(storageConfigProvider.notifier).setWebDav(_davForm);
  }

  Future<void> _testDav() async {
    setState(() {
      _testing = true;
      _davTestResult = null;
    });
    try {
      await WebDavClient(_davForm).test();
      setState(() => _davTestResult = 'ok');
    } catch (e) {
      setState(() => _davTestResult = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _syncNow() async {
    await _saveDav();
    final replaced = await ref.read(syncProvider.notifier).syncNow();
    if (replaced) refreshAllData(ref);
    await _loadFileInfo();
    if (!mounted) return;
    final s = ref.read(syncProvider);
    showSnack(context, s.phase == SyncPhase.error ? 'Lỗi đồng bộ: ${s.message}' : (s.message ?? 'Đã đồng bộ'));
  }

  // ---------------------------------------------------------------------------
  // Đổi nơi lưu
  // ---------------------------------------------------------------------------

  Future<void> _toLocal() async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Chuyển sang lưu trên máy',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Dữ liệu trên Supabase vẫn giữ nguyên. Bạn có muốn chép toàn bộ dữ liệu hiện có về máy này không?',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Chép dữ liệu về máy')),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false), child: const Text('Bắt đầu với dữ liệu trống')),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    setState(() => _switching = true);
    try {
      await switchToLocal(ref, copy: choice);
      await _loadFileInfo();
      if (mounted) showSnack(context, choice ? 'Đã chép dữ liệu về máy' : 'Đã chuyển sang lưu trên máy');
    } catch (e) {
      if (mounted) showSnack(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _toCloud() async {
    final cfg = ref.read(storageConfigProvider);
    final counts = await localDataCount();
    if (!mounted) return;
    final result = await showModalBottomSheet<({String url, String key, bool copy})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SupabaseConnectSheet(
        initialUrl: cfg.supabaseUrl,
        initialKey: cfg.supabaseKey,
        localCustomers: counts.customers,
        localServices: counts.services,
      ),
    );
    if (result == null) return;
    setState(() => _switching = true);
    try {
      await switchToCloud(ref, url: result.url, key: result.key, copyLocal: result.copy);
    } catch (e) {
      if (mounted) showSnack(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(storageConfigProvider);
    final sync = ref.watch(syncProvider);
    final local = cfg.mode == StorageMode.local;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const GlassNavBar(),
      appBar: AppBar(
        toolbarHeight: 76,
        title: const PageTitle('Lưu trữ dữ liệu', icon: Icons.storage_rounded),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: kNavBarSpace),
        children: [
          // Nơi lưu hiện tại
          Card(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconTile(local ? Icons.phone_iphone_rounded : Icons.cloud_rounded,
                      color: Brand.accent, size: 48, gradient: Brand.tileGradient),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(local ? 'Lưu trên máy này' : 'Supabase (đám mây)',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          local
                              ? 'Không cần tài khoản. Nên bật đồng bộ hoặc sao lưu định kỳ.'
                              : 'Đồng bộ mọi thiết bị đăng nhập cùng tài khoản.',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (!local)
            FormSection(
              header: 'Supabase',
              children: [
                FormValueRow(label: 'Máy chủ', value: Uri.tryParse(cfg.supabaseUrl)?.host, onTap: null),
                FormValueRow(
                  label: 'Tài khoản',
                  value: AppGate.instance.supabaseReady
                      ? Supabase.instance.client.auth.currentUser?.email
                      : null,
                  onTap: null,
                ),
              ],
            ),

          if (local) ...[
            FormSection(
              header: 'File dữ liệu',
              children: [
                FormValueRow(
                  label: 'Dung lượng',
                  value: _fileInfo == null ? null : '${(_fileInfo!.size / 1024).toStringAsFixed(1)} KB',
                  onTap: null,
                ),
                FormValueRow(
                  label: 'Sửa lần cuối',
                  value: _fileInfo == null || _fileInfo!.updatedAt.isEmpty
                      ? 'Chưa có dữ liệu'
                      : fmtDate(DateTime.parse(_fileInfo!.updatedAt).toLocal()),
                  onTap: null,
                ),
              ],
            ),

            FormSection(
              header: 'Đồng bộ WebDAV',
              footer: 'Mỗi lần sửa dữ liệu sẽ tự đẩy file lên; mở app thì tự lấy bản mới nhất.\n'
                  'cPanel: Files → Web Disk → tạo tài khoản, URL dạng https://tenmien.com:2078/thumuc/ '
                  '(cũng dùng được Nextcloud, Synology, Koofr, pCloud…).',
              children: [
                FormSwitchRow(
                  label: 'Bật đồng bộ',
                  value: _davOn,
                  onChanged: (v) => _saveDav(enabled: v),
                ),
                FormTextRow(
                  label: 'URL thư mục',
                  controller: _davUrl,
                  hint: 'https://…:2078/amv/',
                  keyboardType: TextInputType.url,
                  onChanged: (_) => _davTestResult = null,
                ),
                FormTextRow(label: 'Tài khoản', controller: _davUser, hint: 'user@tenmien.com'),
                FormTextRow(
                  label: 'Mật khẩu',
                  controller: _davPass,
                  hint: '••••••',
                  obscure: _obscure,
                  trailing: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                FormActionRow(
                  label: 'Kiểm tra kết nối',
                  icon: Icons.wifi_tethering_rounded,
                  busy: _testing,
                  subtitle: switch (_davTestResult) {
                    null => null,
                    'ok' => 'Kết nối & ghi thử thành công ✓',
                    final err => err,
                  },
                  color: _davTestResult == null || _davTestResult == 'ok' ? null : kRed,
                  onTap: _davForm.isComplete ? _testDav : null,
                ),
                FormActionRow(
                  label: 'Đồng bộ ngay',
                  icon: Icons.sync_rounded,
                  busy: sync.phase == SyncPhase.syncing,
                  subtitle: switch (sync.phase) {
                    SyncPhase.off => 'Bật đồng bộ và nhập đủ URL, tài khoản để dùng',
                    SyncPhase.error => 'Lỗi: ${sync.message}',
                    _ when sync.lastSync != null =>
                      '${sync.message ?? 'Đã đồng bộ'} lúc ${TimeOfDay.fromDateTime(sync.lastSync!).format(context)}',
                    _ => null,
                  },
                  onTap: _davOn && _davForm.isComplete ? _syncNow : null,
                ),
              ],
            ),
          ],

          FormSection(
            header: 'Sao lưu thủ công',
            footer: 'File sao lưu lưu được vào Google Drive, iCloud Drive, OneDrive… qua bảng chia sẻ. '
                'Mật khẩu tài khoản trong file vẫn ở dạng mã hoá.',
            children: [
              FormActionRow(
                label: 'Xuất file sao lưu',
                icon: Icons.ios_share_rounded,
                subtitle: 'Lưu vào Google Drive / iCloud / Files',
                onTap: () => exportBackup(context, ref),
              ),
              FormActionRow(
                label: 'Khôi phục từ file',
                icon: Icons.settings_backup_restore_rounded,
                onTap: () async {
                  await importBackup(context, ref);
                  await _loadFileInfo();
                },
              ),
            ],
          ),

          FormSection(
            header: 'Đổi nơi lưu',
            children: [
              local
                  ? FormActionRow(
                      label: 'Chuyển sang Supabase (đám mây)',
                      icon: Icons.cloud_upload_rounded,
                      busy: _switching,
                      onTap: _toCloud,
                    )
                  : FormActionRow(
                      label: 'Chuyển sang lưu trên máy',
                      icon: Icons.phone_iphone_rounded,
                      busy: _switching,
                      onTap: _toLocal,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bảng nhập URL + key Supabase (dùng ở màn chào mừng và khi chuyển sang đám mây).
class SupabaseConnectSheet extends StatefulWidget {
  const SupabaseConnectSheet({
    super.key,
    required this.initialUrl,
    required this.initialKey,
    this.localCustomers = 0,
    this.localServices = 0,
  });

  final String initialUrl;
  final String initialKey;

  /// Dữ liệu đang lưu trên máy (có dữ liệu thì hỏi có chép lên Supabase không).
  final int localCustomers;
  final int localServices;

  bool get hasLocal => localCustomers > 0 || localServices > 0;

  @override
  State<SupabaseConnectSheet> createState() => _SupabaseConnectSheetState();
}

class _SupabaseConnectSheetState extends State<SupabaseConnectSheet> {
  late final _url = TextEditingController(text: widget.initialUrl);
  late final _key = TextEditingController(text: widget.initialKey);
  late bool _copy = widget.hasLocal;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await testSupabase(_url.text, _key.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.pop(context, (url: _url.text.trim(), key: _key.text.trim(), copy: _copy));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Kết nối Supabase',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            FormSection(
              footer: 'Lấy ở Supabase → Project Settings → API. Project mới cần chạy file '
                  'supabase/schema.sql trong SQL Editor trước.',
              children: [
                FormTextRow(
                  label: 'Project URL',
                  controller: _url,
                  hint: 'https://xxxx.supabase.co',
                  keyboardType: TextInputType.url,
                ),
                FormTextRow(label: 'Publishable key', controller: _key, hint: 'sb_publishable_…'),
              ],
            ),
            if (widget.hasLocal)
              FormSection(
                footer: 'Đăng nhập xong sẽ chép ${widget.localCustomers} khách hàng, '
                    '${widget.localServices} dịch vụ (cùng tài khoản, lịch sử gia hạn) '
                    'đang lưu trên máy lên Supabase.',
                children: [
                  FormSwitchRow(
                    label: 'Chép dữ liệu trên máy lên',
                    value: _copy,
                    onChanged: (v) => setState(() => _copy = v),
                  ),
                ],
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
                child: Text(_error!, style: const TextStyle(color: kRed)),
              ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _busy ? null : _connect,
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Kết nối'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
