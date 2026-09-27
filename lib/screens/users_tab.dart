import 'dart:async';

import 'package:flutter/material.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/speed_tracker.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';
import 'user_detail_screen.dart';
import 'user_form_screen.dart';

enum UserFilter { all, online, active, disabled, expired, limited }

class UsersTab extends StatefulWidget {
  const UsersTab({super.key, required this.api, this.initialFilter = UserFilter.all});

  final PanelApi api;
  final UserFilter initialFilter;

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  List<PanelUser> _users = [];
  bool _loading = true;
  Object? _error;
  String _query = '';
  late UserFilter _filter = widget.initialFilter;
  final Set<String> _toggling = {};
  final _tracker = SpeedTracker();
  Map<String, Speed> _speeds = {};
  Timer? _timer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Live speed: poll traffic counters while this page is on screen.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_polling && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    _polling = true;
    try {
      final users = await widget.api.users();
      if (!mounted) return;
      setState(() {
        _users = users;
        _speeds = _tracker.update(users, DateTime.now());
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      if (_users.isNotEmpty) showSnack(context, '$e', error: true);
    } finally {
      _polling = false;
    }
  }

  bool _match(PanelUser u, UserFilter f) => switch (f) {
        UserFilter.all => true,
        UserFilter.online => u.online,
        UserFilter.active => u.status == UserStatus.active,
        UserFilter.disabled => u.status == UserStatus.disabled,
        UserFilter.expired => u.status == UserStatus.expired,
        UserFilter.limited => u.status == UserStatus.limited,
      };

  List<PanelUser> get _visible => _users
      .where((u) =>
          _match(u, _filter) &&
          (_query.isEmpty ||
              u.name.toLowerCase().contains(_query) ||
              (u.note ?? '').toLowerCase().contains(_query)))
      .toList();

  Future<void> _toggle(PanelUser u, bool enabled) async {
    setState(() => _toggling.add(u.key));
    try {
      await widget.api.setEnabled(u, enabled);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _toggling.remove(u.key));
    }
  }

  Future<void> _open(PanelUser u) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => UserDetailScreen(api: widget.api, user: u)));
    _load();
  }

  Future<void> _add() async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => UserFormScreen(api: widget.api)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        tooltip: s.t('add_user'),
        onPressed: _add,
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: s.t('search_users'),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                for (final f in UserFilter.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: Text(
                          '${s.t('filter_${f.name}')} (${_users.where((u) => _match(u, f)).length})'),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  Widget _body(S s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _users.isEmpty) {
      return ErrorView(
          message: '$_error',
          onRetry: () {
            setState(() => _loading = true);
            _load();
          });
    }
    final list = _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: list.isEmpty
          ? ListView(children: [
              SizedBox(
                  height: 300,
                  child: EmptyView(icon: Icons.person_search_outlined, title: s.t('no_users'))),
            ])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
              itemCount: list.length,
              itemBuilder: (_, i) => _UserTile(
                user: list[i],
                speed: _speeds[list[i].key] ?? Speed.zero,
                toggling: _toggling.contains(list[i].key),
                onTap: () => _open(list[i]),
                onToggle: (v) => _toggle(list[i], v),
              ),
            ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.speed,
    required this.toggling,
    required this.onTap,
    required this.onToggle,
  });

  final PanelUser user;
  final Speed speed;
  final bool toggling;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final muted = SoftColors.of(context).muted;
    final u = user;
    final sub = [
      s.status(u.status),
      if (u.inboundName != null) u.inboundName!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoftBox(
        radius: 22,
        depth: 5,
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
        onTap: onTap,
        child: Column(
          children: [
            Row(
              children: [
                _StatusDot(user: u),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: statusColor(u.status))),
                    ],
                  ),
                ),
                Switch(value: u.enabled, onChanged: toggling ? null : onToggle),
              ],
            ),
            if (speed.active) ...[
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SpeedChip(speed: speed),
              ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: u.usage ?? 0,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: usageColor(u.usage),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Row(
                children: [
                  Flexible(
                    child: Text(fmtTraffic(u, s),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodySmall),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(fmtExpiry(u, s),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live upload/download speed tag.
class SpeedChip extends StatelessWidget {
  const SpeedChip({super.key, required this.speed});

  final Speed speed;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF3B82F6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '↑ ${fmtSpeed(speed.up)}   ↓ ${fmtSpeed(speed.down)}',
        textDirection: TextDirection.ltr,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.user});

  final PanelUser user;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(user.status);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase()),
        ),
        if (user.online)
          PositionedDirectional(
            end: -1,
            bottom: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: okColor,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
