import '../models/models.dart';
import '../utils/json.dart';
import 'http.dart';
import 'panel_api.dart';

/// Marzban REST API (bearer token from /api/admin/token or a pasted token).
class MarzbanApi extends PanelApi {
  MarzbanApi(super.config) : _http = PanelHttp(allowInsecure: config.allowInsecure);

  final PanelHttp _http;

  @override
  UserFormKind get userFormKind => UserFormKind.marzban;
  String? _token;

  bool get _hasCreds => config.username.isNotEmpty && config.password.isNotEmpty;

  Uri _u(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('${config.baseUrl}$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  String _enc(String s) => Uri.encodeComponent(s);

  String? _detail(dynamic j) {
    if (j is! Map) return null;
    final d = j['detail'];
    if (d is String) return d;
    if (d is List) {
      return d.map((e) {
        if (e is Map) {
          final loc = e['loc'];
          final field = loc is List && loc.isNotEmpty ? '${loc.last}: ' : '';
          return '$field${e['msg']}';
        }
        return e.toString();
      }).join('\n');
    }
    return d?.toString();
  }

  Future<void> _passwordLogin() async {
    final r = await _http.send('POST', _u('/api/admin/token'), form: {
      'grant_type': 'password',
      'username': config.username,
      'password': config.password,
    });
    final j = r.json;
    if (r.ok && j is Map && j['access_token'] != null) {
      _token = j['access_token'].toString();
      return;
    }
    if (r.status == 404) {
      throw ApiException('Marzban API not found (404). Check the panel URL.', 404);
    }
    throw ApiException(_detail(j) ?? 'Login failed (HTTP ${r.status}).', r.status);
  }

  @override
  Future<void> login() async {
    if (_hasCreds) {
      await _passwordLogin();
    } else {
      _token = config.token;
      await _call('GET', '/api/admin');
    }
  }

  Future<dynamic> _call(String method, String path,
      {Object? json, Map<String, String>? query}) async {
    if (_token == null) {
      if (_hasCreds) {
        await _passwordLogin();
      } else {
        _token = config.token;
      }
    }
    Future<HttpResult> go() => _http.send(method, _u(path, query),
        json: json, headers: {'Authorization': 'Bearer $_token'});
    var r = await go();
    if ((r.status == 401 || r.status == 403) && _hasCreds) {
      await _passwordLogin();
      r = await go();
    }
    if (!r.ok) {
      if (r.status == 401) {
        throw ApiException(_detail(r.json) ?? 'Token is invalid or expired.', 401);
      }
      throw ApiException(_detail(r.json) ?? 'HTTP ${r.status} on $path', r.status);
    }
    return r.json;
  }

  @override
  Future<ServerStats> status() async {
    final sys = asMap(await _call('GET', '/api/system'));
    var core = <String, dynamic>{};
    try {
      core = asMap(await _call('GET', '/api/core'));
    } catch (_) {}
    return ServerStats(
      cpu: asDouble(sys['cpu_usage']),
      cpuCores: asInt(sys['cpu_cores']),
      memUsed: asInt(sys['mem_used']),
      memTotal: asInt(sys['mem_total']),
      netUpSpeed: asInt(sys['outgoing_bandwidth_speed']),
      netDownSpeed: asInt(sys['incoming_bandwidth_speed']),
      netSent: asInt(sys['outgoing_bandwidth']),
      netRecv: asInt(sys['incoming_bandwidth']),
      coreState: core.isEmpty ? null : (core['started'] == true ? 'running' : 'stop'),
      coreVersion: asStr(core['version']),
      panelVersion: asStr(sys['version']),
      totalUsers: asInt(sys['total_user']),
      activeUsers: asInt(sys['users_active']),
      onlineUsers: asInt(sys['online_users']),
      disabledUsers: asInt(sys['users_disabled']),
      expiredUsers: asInt(sys['users_expired']),
      limitedUsers: asInt(sys['users_limited']),
      onHoldUsers: asInt(sys['users_on_hold']),
    );
  }

  DateTime? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    var v = s;
    // Marzban returns naive UTC timestamps.
    if (!v.endsWith('Z') && !RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v)) v = '${v}Z';
    return DateTime.tryParse(v)?.toUtc();
  }

  PanelUser _toUser(Map<String, dynamic> u) {
    final name = asStr(u['username']) ?? '';
    final status = switch (asStr(u['status'])) {
      'disabled' => UserStatus.disabled,
      'expired' => UserStatus.expired,
      'limited' => UserStatus.limited,
      'on_hold' => UserStatus.onHold,
      _ => UserStatus.active,
    };
    final exp = asInt(u['expire']) ?? 0;
    final onlineAt = _parseTime(asStr(u['online_at']));
    var sub = asStr(u['subscription_url']) ?? '';
    if (sub.startsWith('/')) {
      final base = Uri.parse(config.baseUrl);
      sub = '${base.scheme}://${base.authority}$sub';
    }
    final hold = asInt(u['on_hold_expire_duration']);
    return PanelUser(
      key: name,
      name: name,
      enabled: status != UserStatus.disabled,
      status: status,
      down: asInt(u['used_traffic']) ?? 0,
      total: asInt(u['data_limit']) ?? 0,
      expiry: exp > 0 ? DateTime.fromMillisecondsSinceEpoch(exp * 1000) : null,
      expiryDaysAfterFirstUse:
          status == UserStatus.onHold && hold != null && hold > 0 ? (hold / 86400).round() : null,
      online: onlineAt != null &&
          DateTime.now().toUtc().difference(onlineAt).inSeconds.abs() < 120,
      lastOnline: onlineAt?.toLocal(),
      subUrl: sub.isEmpty ? null : sub,
      links: asList(u['links']).map((e) => e.toString()).toList(),
      note: asStr(u['note']),
      protocol: asMap(u['proxies']).keys.join(', '),
      raw: u,
    );
  }

  @override
  Future<List<PanelUser>> users() async {
    final all = <PanelUser>[];
    var offset = 0;
    const limit = 500;
    while (true) {
      final j = asMap(await _call('GET', '/api/users',
          query: {'offset': '$offset', 'limit': '$limit'}));
      final list = asList(j['users']);
      all.addAll(list.map((e) => _toUser(asMap(e))));
      offset += list.length;
      final total = asInt(j['total']) ?? offset;
      if (list.isEmpty || offset >= total) break;
    }
    return all;
  }

  @override
  Future<List<InboundInfo>> inbounds() async {
    final j = asMap(await _call('GET', '/api/inbounds'));
    final out = <InboundInfo>[];
    j.forEach((proto, list) {
      for (final e in asList(list)) {
        final m = asMap(e);
        final tag = asStr(m['tag']) ?? '';
        out.add(InboundInfo(
          tag: tag,
          remark: tag,
          protocol: asStr(m['protocol']) ?? proto,
          port: asInt(m['port']),
          network: asStr(m['network']),
          security: asStr(m['tls']),
        ));
      }
    });
    return out;
  }

  int _expireSeconds(UserDraft d) =>
      d.expiry == null ? 0 : d.expiry!.millisecondsSinceEpoch ~/ 1000;

  @override
  Future<void> createUser(UserDraft d) async {
    final ibs = await inbounds();
    final protos = d.protocols.isEmpty ? ibs.map((e) => e.protocol).toSet() : d.protocols;
    final proxies = <String, dynamic>{};
    final inb = <String, List<String>>{};
    for (final p in protos) {
      proxies[p] = p == 'vless' ? {'flow': d.flow} : <String, dynamic>{};
      inb[p] = ibs.where((e) => e.protocol == p).map((e) => e.tag).toList();
    }
    final holdDays = d.expiryDaysAfterFirstUse ?? 0;
    final body = <String, dynamic>{
      'username': d.name,
      'proxies': proxies,
      'inbounds': inb,
      'expire': holdDays > 0 ? 0 : _expireSeconds(d),
      'data_limit': d.totalBytes,
      'data_limit_reset_strategy': 'no_reset',
      'status': holdDays > 0 ? 'on_hold' : 'active',
      'note': d.note,
    };
    if (holdDays > 0) body['on_hold_expire_duration'] = holdDays * 86400;
    await _call('POST', '/api/user', json: body);
    if (!d.enabled) {
      await _call('PUT', '/api/user/${_enc(d.name)}', json: {'status': 'disabled'});
    }
  }

  @override
  Future<void> updateUser(PanelUser u, UserDraft d) async {
    final body = <String, dynamic>{'data_limit': d.totalBytes, 'note': d.note};
    final holdDays = d.expiryDaysAfterFirstUse ?? 0;
    if (!d.enabled) {
      body['status'] = 'disabled';
      body['expire'] = _expireSeconds(d);
    } else if (holdDays > 0) {
      body['status'] = 'on_hold';
      body['on_hold_expire_duration'] = holdDays * 86400;
      body['expire'] = 0;
    } else {
      body['expire'] = _expireSeconds(d);
      if (u.status == UserStatus.disabled || u.status == UserStatus.onHold) {
        body['status'] = 'active';
      }
    }
    await _call('PUT', '/api/user/${_enc(u.name)}', json: body);
  }

  @override
  Future<void> setEnabled(PanelUser u, bool enabled) =>
      _call('PUT', '/api/user/${_enc(u.name)}',
          json: {'status': enabled ? 'active' : 'disabled'});

  @override
  Future<void> deleteUser(PanelUser u) => _call('DELETE', '/api/user/${_enc(u.name)}');

  @override
  Future<void> resetTraffic(PanelUser u) =>
      _call('POST', '/api/user/${_enc(u.name)}/reset');

  @override
  Future<void> restartCore() => _call('POST', '/api/core/restart');

  @override
  void dispose() => _http.close();
}
