import 'dart:convert';

import '../models/models.dart';
import '../utils/json.dart';
import '../utils/random.dart';
import 'http.dart';
import 'panel_api.dart';
import 'xui_links.dart';

/// 3X-UI (MHSanaei) and Alireza X-UI. Auth is either a cookie session from
/// POST /login or, on 3X-UI 3.x, an API token sent as a Bearer header. API
/// routes differ between versions, so they are detected once.
class XuiApi extends PanelApi {
  XuiApi(super.config) : _http = PanelHttp(allowInsecure: config.allowInsecure);

  final PanelHttp _http;
  bool _loggedIn = false;
  Future<void>? _loginOp;

  String? _prefix; // e.g. /panel/api/inbounds
  String? _listPath; // e.g. /list
  int? _statusIdx;
  Map<String, dynamic>? _subSettings;
  bool _subTried = false;
  String? _onlinesPath;
  bool? _v3; // 3X-UI 3.x client catalog (/panel/api/clients)
  bool _onlinesUnsupported = false;
  List<Map<String, dynamic>> _rawInbounds = [];

  static const _listCandidates = [
    ['/panel/api/inbounds', '/list'],
    ['/xui/API/inbounds', '/'],
    ['/xui/API/inbounds', '/list'],
  ];

  static const _statusCandidates = [
    ['GET', '/panel/api/server/status'],
    ['POST', '/server/status'],
    ['POST', '/panel/server/status'],
  ];

  static const _restartCandidates = [
    '/panel/api/server/restartXrayService',
    '/server/restartXrayService',
    '/panel/server/restartXrayService',
  ];

  static const _clientProtocols = {'vmess', 'vless', 'trojan', 'shadowsocks'};

  // 3.x attaches clients to every protocol except these (proxies, tunnels, TUN).
  static const _noClientProtocols = {
    'socks', 'http', 'mixed', 'tunnel', 'dokodemo-door', 'dokodemo', 'tun'
  };

  Uri _u(String path) => Uri.parse('${config.baseUrl}$path');

  bool get _tokenMode => config.token.isNotEmpty;

  Map<String, String>? get _authHeaders =>
      _tokenMode ? {'Authorization': 'Bearer ${config.token}'} : null;

  @override
  Future<void> login() async {
    if (_tokenMode) {
      // No session needed; just verify the token against a read-only route.
      final r = await _http.send('GET', _u('/panel/api/server/status'), headers: _authHeaders);
      final j = r.json;
      if (r.ok && j is Map && j['success'] == true) {
        _loggedIn = true;
        return;
      }
      if (r.status == 401 || r.status == 403) {
        throw ApiException('API token was rejected by the panel.', r.status);
      }
      throw ApiException(
          'API token not accepted (HTTP ${r.status}). Check the URL and secret path; '
          'token login needs 3X-UI 3.x.',
          r.status);
    }
    _loggedIn = false;
    _http.cookies.clear();
    final r = await _http.send('POST', _u('/login'),
        form: {'username': config.username, 'password': config.password});
    final j = r.json;
    if (j is Map && j['success'] == true) {
      _loggedIn = true;
      return;
    }
    final msg = j is Map ? (j['msg']?.toString() ?? '') : '';
    if (msg.isNotEmpty) throw ApiException(msg, r.status);
    if (r.status == 404) {
      throw ApiException(
          'Panel not found (404). Check the URL, including the secret web base path.',
          404);
    }
    throw ApiException('Login failed (HTTP ${r.status}).', r.status);
  }

  Future<void> _ensureLogin() {
    if (_loggedIn) return Future.value();
    return _loginOp ??= login().whenComplete(() => _loginOp = null);
  }

  // 3x-ui answers 404 to unauthenticated API calls; older builds redirect.
  bool _authLost(HttpResult r) =>
      r.status == 401 ||
      r.status == 404 ||
      (r.status >= 300 && r.status < 400) ||
      (r.ok && r.json == null);

  Future<dynamic> _call(String method, String path,
      {Map<String, String>? form, Object? json}) async {
    HttpResult r;
    if (_tokenMode) {
      r = await _http.send(method, _u(path), form: form, json: json, headers: _authHeaders);
      if (r.status == 401 || r.status == 403) {
        throw ApiException('API token was rejected by the panel.', r.status);
      }
    } else {
      await _ensureLogin();
      r = await _http.send(method, _u(path), form: form, json: json);
      if (_authLost(r)) {
        _loggedIn = false;
        await _ensureLogin();
        r = await _http.send(method, _u(path), form: form, json: json);
      }
    }
    if (r.status == 404 || (r.status >= 300 && r.status < 400)) {
      throw NotFoundException(path);
    }
    final j = r.json;
    if (!r.ok || j is! Map) {
      throw ApiException('Unexpected response (HTTP ${r.status}) from $path', r.status);
    }
    if (j['success'] != true) {
      throw ApiException((j['msg'] ?? 'Request failed').toString());
    }
    return j['obj'];
  }

  Future<List<Map<String, dynamic>>> _fetchInbounds() async {
    List<dynamic>? list;
    if (_prefix != null) {
      list = asList(await _call('GET', '$_prefix$_listPath'));
    } else {
      for (final c in _listCandidates) {
        try {
          list = asList(await _call('GET', '${c[0]}${c[1]}'));
          _prefix = c[0];
          _listPath = c[1];
          break;
        } on NotFoundException {
          continue;
        }
      }
      if (list == null) {
        throw ApiException(_tokenMode
            ? 'Inbounds API not found or API token not accepted. Check the URL and token.'
            : 'Inbounds API not found on this panel. Is the panel type correct?');
      }
    }
    _rawInbounds = list.map(asMap).toList();
    return _rawInbounds;
  }

  Future<Set<String>> _onlines() async {
    if (_onlinesUnsupported) return {};
    // 3X-UI 3.x moved the route under /panel/api/clients.
    final paths = _onlinesPath != null
        ? [_onlinesPath!]
        : ['/panel/api/clients/onlines', '$_prefix/onlines'];
    for (final p in paths) {
      try {
        final obj = await _call('POST', p);
        _onlinesPath = p;
        return asList(obj).map((e) => e.toString()).toSet();
      } on NotFoundException {
        continue;
      } catch (_) {
        return {};
      }
    }
    // Fall back to clientStats.lastOnline.
    _onlinesUnsupported = true;
    return {};
  }

  Future<void> _loadSubSettings() async {
    if (_subTried) return;
    _subTried = true;
    for (final p in ['/panel/api/setting/all', '/panel/setting/all', '/xui/setting/all']) {
      try {
        _subSettings = asMap(await _call('POST', p));
        return;
      } catch (_) {}
    }
  }

  String? _subUrl(String subId) {
    final s = _subSettings;
    if (s == null || subId.isEmpty || s['subEnable'] != true) return null;
    final uri = asStr(s['subURI']) ?? '';
    if (uri.isNotEmpty) return uri.endsWith('/') ? '$uri$subId' : '$uri/$subId';
    final https = (asStr(s['subCertFile']) ?? '').isNotEmpty;
    final scheme = https ? 'https' : 'http';
    var domain = asStr(s['subDomain']) ?? '';
    if (domain.isEmpty) domain = config.host;
    final port = asInt(s['subPort']) ?? (https ? 443 : 80);
    var path = asStr(s['subPath']) ?? '/sub/';
    if (!path.startsWith('/')) path = '/$path';
    if (!path.endsWith('/')) path = '$path/';
    final portPart = (https && port == 443) || (!https && port == 80) ? '' : ':$port';
    return '$scheme://$domain$portPart$path$subId';
  }

  @override
  Future<ServerStats> status() async {
    final order = _statusIdx != null
        ? [_statusIdx!]
        : List<int>.generate(_statusCandidates.length, (i) => i);
    for (final i in order) {
      final c = _statusCandidates[i];
      try {
        final obj = asMap(await _call(c[0], c[1]));
        _statusIdx = i;
        return _parseStatus(obj);
      } on NotFoundException {
        continue;
      }
    }
    throw ApiException('Server status API not found on this panel.');
  }

  ServerStats _parseStatus(Map<String, dynamic> j) {
    final mem = asMap(j['mem']);
    final disk = asMap(j['disk']);
    final swap = asMap(j['swap']);
    final netIO = asMap(j['netIO']);
    final netTraffic = asMap(j['netTraffic']);
    final xray = asMap(j['xray']);
    final ip = asMap(j['publicIP']);
    final app = asMap(j['appStats']);
    String? cleanIp(dynamic v) {
      final s = asStr(v) ?? '';
      return s.isEmpty || s == 'N/A' ? null : s;
    }

    return ServerStats(
      cpu: asDouble(j['cpu']),
      cpuCores: asInt(j['cpuCores']),
      memUsed: asInt(mem['current']),
      memTotal: asInt(mem['total']),
      diskUsed: asInt(disk['current']),
      diskTotal: asInt(disk['total']),
      swapUsed: asInt(swap['current']),
      swapTotal: asInt(swap['total']),
      uptime: asInt(j['uptime']),
      loads: asList(j['loads']).map(asDouble).whereType<double>().toList(),
      netUpSpeed: asInt(netIO['up']),
      netDownSpeed: asInt(netIO['down']),
      netSent: asInt(netTraffic['sent']),
      netRecv: asInt(netTraffic['recv']),
      coreState: asStr(xray['state']),
      coreVersion: asStr(xray['version']),
      coreError: asStr(xray['errorMsg']),
      panelVersion: asStr(j['panelVersion']),
      tcpCount: asInt(j['tcpCount']),
      udpCount: asInt(j['udpCount']),
      ipv4: cleanIp(ip['ipv4']),
      ipv6: cleanIp(ip['ipv6']),
      logicalCores: asInt(j['logicalPro']),
      cpuMhz: asDouble(j['cpuSpeedMhz']),
      appMem: asInt(app['mem']),
      appThreads: asInt(app['threads']),
      appUptime: asInt(app['uptime']),
    );
  }

  /// The 3.x client catalog, or null on older panels.
  Future<List<dynamic>?> _clientCatalog() async {
    if (_v3 == false) return null;
    try {
      final list = asList(await _call('GET', '/panel/api/clients/list'));
      _v3 = true;
      return list;
    } on NotFoundException {
      _v3 = false;
      return null;
    }
  }

  Future<bool> _isV3() async => _v3 ?? (await _clientCatalog()) != null;

  @override
  bool get supportsMultiInbound => _v3 == true;

  @override
  UserFormKind get userFormKind => _v3 == true ? UserFormKind.xuiV3 : UserFormKind.xuiLegacy;

  @override
  bool get canManageInbounds => true;

  @override
  bool get hasPanelSettings => true;

  @override
  Future<void> prepare() => _isV3();

  @override
  Future<List<String>?> fetchLinks(PanelUser user) async {
    if (!await _isV3()) return null;
    try {
      final obj = await _call('GET', '/panel/api/clients/links/${_enc(user.name)}');
      return asList(obj).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return null;
    }
  }

  static (DateTime?, int?) _parseExpiry(int raw) {
    if (raw > 0) return (DateTime.fromMillisecondsSinceEpoch(raw), null);
    if (raw < 0) return (null, (-raw / 86400000).round());
    return (null, null);
  }

  static UserStatus _statusOf(bool enabled, DateTime? expiry, int total, int used, DateTime now) =>
      !enabled
          ? UserStatus.disabled
          : (expiry != null && expiry.isBefore(now))
              ? UserStatus.expired
              : (total > 0 && used >= total)
                  ? UserStatus.limited
                  : UserStatus.active;

  static bool _recentlyOnline(int lastOnlineMs, DateTime now) =>
      lastOnlineMs > 0 && now.millisecondsSinceEpoch - lastOnlineMs < 180000;

  /// 3.x: one user per catalog client, merged across its inbounds.
  List<PanelUser> _catalogUsers(
      List<dynamic> catalog, List<Map<String, dynamic>> inbounds, Set<String> online) {
    final now = DateTime.now();
    final byId = {for (final ib in inbounds) asInt(ib['id']): ib};
    return catalog.map((e) {
      final c = asMap(e);
      final email = asStr(c['email']) ?? '';
      final tr = asMap(c['traffic']);
      final enabled = c['enable'] != false;
      final up = asInt(tr['up']) ?? 0;
      final down = asInt(tr['down']) ?? 0;
      final total = asInt(c['totalGB']) ?? 0;
      final (expiry, afterFirstUse) = _parseExpiry(asInt(c['expiryTime']) ?? 0);
      final lastOnline = asInt(tr['lastOnline']) ?? 0;
      final ids = asList(c['inboundIds']).map(asInt).whereType<int>().toList();
      final attached = ids.map((id) => byId[id]).whereType<Map<String, dynamic>>().toList();
      final links = <String>[];
      for (final ib in attached) {
        final rec = asList(asMap(ib['settings'])['clients'])
                .map(asMap)
                .where((x) => asStr(x['email']) == email)
                .firstOrNull ??
            c;
        links.addAll(buildXuiLinks(ib, rec, config.host));
      }
      final names = attached.map((ib) {
        final r = asStr(ib['remark']) ?? '';
        return r.isNotEmpty ? r : '${ib['protocol']}:${ib['port']}';
      }).toList();
      return PanelUser(
        key: 'c:$email',
        name: email,
        enabled: enabled,
        status: _statusOf(enabled, expiry, total, up + down, now),
        up: up,
        down: down,
        total: total,
        expiry: expiry,
        expiryDaysAfterFirstUse: afterFirstUse,
        online: online.contains(email) || _recentlyOnline(lastOnline, now),
        lastOnline: lastOnline > 0 ? DateTime.fromMillisecondsSinceEpoch(lastOnline) : null,
        subUrl: _subUrl(asStr(c['subId']) ?? ''),
        links: links,
        note: asStr(c['comment']),
        limitIp: asInt(c['limitIp']),
        inboundId: ids.isEmpty ? null : ids.first,
        inboundName: names.isEmpty
            ? null
            : names.length <= 2
                ? names.join(', ')
                : '${names.take(2).join(', ')} +${names.length - 2}',
        protocol: attached.map((ib) => asStr(ib['protocol']) ?? '').toSet().join(', '),
        raw: c,
      );
    }).toList();
  }

  @override
  Future<List<PanelUser>> users() async {
    final catalog = await _clientCatalog();
    final inbounds = await _fetchInbounds();
    final online = await _onlines();
    await _loadSubSettings();
    if (catalog != null) return _catalogUsers(catalog, inbounds, online);
    final now = DateTime.now();
    final result = <PanelUser>[];
    for (final ib in inbounds) {
      final protocol = asStr(ib['protocol']) ?? '';
      final inboundId = asInt(ib['id']);
      final remark = asStr(ib['remark']) ?? '';
      final settings = asMap(ib['settings']);
      final stats = <String, Map<String, dynamic>>{};
      for (final s in asList(ib['clientStats'])) {
        final m = asMap(s);
        stats[asStr(m['email']) ?? ''] = m;
      }
      for (final c in asList(settings['clients'])) {
        final client = asMap(c);
        final email = asStr(client['email']) ?? '';
        final st = stats[email] ?? const <String, dynamic>{};
        final enabled = client['enable'] != false;
        final up = asInt(st['up']) ?? 0;
        final down = asInt(st['down']) ?? 0;
        final total = asInt(client['totalGB']) ?? asInt(st['total']) ?? 0;
        final (expiry, afterFirstUse) =
            _parseExpiry(asInt(client['expiryTime']) ?? asInt(st['expiryTime']) ?? 0);
        final lastOnline = asInt(st['lastOnline']) ?? 0;
        final status = _statusOf(enabled, expiry, total, up + down, now);
        result.add(PanelUser(
          key: '$inboundId:$email',
          name: email,
          enabled: enabled,
          status: status,
          up: up,
          down: down,
          total: total,
          expiry: expiry,
          expiryDaysAfterFirstUse: afterFirstUse,
          online: online.contains(email) || _recentlyOnline(lastOnline, now),
          lastOnline: lastOnline > 0 ? DateTime.fromMillisecondsSinceEpoch(lastOnline) : null,
          subUrl: _subUrl(asStr(client['subId']) ?? ''),
          links: buildXuiLinks(ib, client, config.host),
          note: asStr(client['comment']),
          limitIp: asInt(client['limitIp']),
          inboundId: inboundId,
          inboundName: remark.isNotEmpty ? remark : '${protocol.toUpperCase()}:${ib['port']}',
          protocol: protocol,
          raw: client,
        ));
      }
    }
    return result;
  }

  @override
  Future<List<InboundInfo>> inbounds() async {
    final list = await _fetchInbounds();
    return list.map((ib) {
      final stream = asMap(ib['streamSettings']);
      final clients = asList(asMap(ib['settings'])['clients']);
      final exp = asInt(ib['expiryTime']) ?? 0;
      return InboundInfo(
        id: asInt(ib['id']),
        tag: asStr(ib['tag']) ?? '',
        remark: asStr(ib['remark']) ?? '',
        protocol: asStr(ib['protocol']) ?? '',
        port: asInt(ib['port']),
        network: asStr(stream['network']),
        security: asStr(stream['security']),
        enabled: ib['enable'] != false,
        up: asInt(ib['up']),
        down: asInt(ib['down']),
        total: asInt(ib['total']),
        clientCount: clients.length,
        expiry: exp > 0 ? DateTime.fromMillisecondsSinceEpoch(exp) : null,
      );
    }).toList();
  }

  /// Inbounds that accept clients (used by the create-user form).
  static bool supportsClients(InboundInfo i, {bool v3 = false}) => v3
      ? !_noClientProtocols.contains(i.protocol)
      : _clientProtocols.contains(i.protocol);

  @override
  bool acceptsClients(InboundInfo inbound) => supportsClients(inbound, v3: _v3 == true);

  @override
  bool get canAttachClients => _v3 == true;

  @override
  Future<List<String>> groups() async {
    if (await _isV3()) {
      try {
        final list = asList(await _call('GET', '/panel/api/clients/groups'));
        final names = [
          for (final g in list)
            if ((asStr(asMap(g)['name']) ?? '').isNotEmpty) asStr(asMap(g)['name'])!,
        ];
        if (names.isNotEmpty) return names;
      } on NotFoundException {
        // Older 3.x builds: fall back to the labels on users.
      }
    }
    final names = <String>{
      for (final u in await users())
        if ((asStr(u.raw['group']) ?? '').isNotEmpty) asStr(u.raw['group'])!,
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  @override
  Future<List<String>> groupEmails(String group) async {
    try {
      return asList(await _call(
              'GET', '/panel/api/clients/groups/${Uri.encodeComponent(group)}/emails'))
          .map((e) => '$e')
          .toList();
    } on NotFoundException {
      return [
        for (final u in await users())
          if (asStr(u.raw['group']) == group) u.name,
      ];
    }
  }

  @override
  Future<int> attachClients(int inboundId, List<String> emails) async {
    if (!await _isV3()) throw ApiException('Needs 3X-UI 3.x.');
    final res = asMap(await _call('POST', '/panel/api/clients/bulkAttach', json: {
      'emails': emails,
      'inboundIds': [inboundId],
    }));
    final attached = res['attached'];
    return attached is List ? attached.length : emails.length;
  }

  int _expiryValue(UserDraft d) {
    final days = d.expiryDaysAfterFirstUse ?? 0;
    if (days > 0) return -days * 86400000;
    return d.expiry?.millisecondsSinceEpoch ?? 0;
  }

  String _clientId(PanelUser u) {
    final c = u.raw;
    return switch (u.protocol) {
      'trojan' => asStr(c['password']) ?? '',
      'shadowsocks' => asStr(c['email']) ?? '',
      _ => asStr(c['id']) ?? '',
    };
  }

  String _enc(String s) => Uri.encodeComponent(s);

  @override
  Future<void> createUser(UserDraft d) async {
    if (await _isV3()) return _createV3(d);
    if (_prefix == null || _rawInbounds.isEmpty) await _fetchInbounds();
    final ib = _rawInbounds.firstWhere((e) => asInt(e['id']) == d.inboundId,
        orElse: () => throw ApiException('Inbound not found.'));
    final protocol = asStr(ib['protocol']) ?? '';
    final settings = asMap(ib['settings']);
    final existing = asList(settings['clients']).map(asMap).toList();
    final client = <String, dynamic>{
      'email': d.name,
      'limitIp': d.limitIp,
      'totalGB': d.totalBytes,
      'expiryTime': _expiryValue(d),
      'enable': d.enabled,
      'subId': randomString(16),
      'comment': d.note,
      'reset': 0,
    };
    switch (protocol) {
      case 'vmess':
        client['id'] = uuidV4();
        client['security'] = 'auto';
      case 'vless':
        client['id'] = uuidV4();
        // Reuse the inbound's flow (e.g. xtls-rprx-vision on Reality).
        client['flow'] = existing.isNotEmpty ? (asStr(existing.first['flow']) ?? '') : '';
      case 'trojan':
        client['password'] = randomString(12);
      case 'shadowsocks':
        final method = asStr(settings['method']) ?? '';
        final is2022 = method.startsWith('2022');
        client['method'] = is2022 ? '' : method;
        client['password'] =
            is2022 ? randomBase64Key(method.contains('128') ? 16 : 32) : randomString(16);
      default:
        throw ApiException('Protocol "$protocol" does not support clients.');
    }
    client.addAll(_legacyExtra(d.extra));
    await _call('POST', '$_prefix/addClient', form: {
      'id': '${d.inboundId}',
      'settings': jsonEncode({
        'clients': [client]
      }),
    });
  }

  /// 3.x: POST /panel/api/clients/add; secrets are generated server-side.
  Future<void> _createV3(UserDraft d) async {
    final ids = d.inboundIds.isNotEmpty ? d.inboundIds.toList() : [if (d.inboundId != null) d.inboundId!];
    if (ids.isEmpty) throw ApiException('Select at least one inbound.');
    if (_rawInbounds.isEmpty) await _fetchInbounds();
    // Reuse the flow of existing VLESS clients (e.g. xtls-rprx-vision).
    var flow = '';
    for (final ib in _rawInbounds.where((e) => ids.contains(asInt(e['id'])))) {
      if (asStr(ib['protocol']) != 'vless') continue;
      flow = asList(asMap(ib['settings'])['clients'])
          .map((c) => asStr(asMap(c)['flow']) ?? '')
          .firstWhere((f) => f.isNotEmpty, orElse: () => '');
      if (flow.isNotEmpty) break;
    }
    final client = <String, dynamic>{
      'email': d.name,
      'totalGB': d.totalBytes,
      'expiryTime': _expiryValue(d),
      'limitIp': d.limitIp,
      'enable': d.enabled,
      'comment': d.note,
      'tgId': 0,
      'subId': randomString(16),
      if (flow.isNotEmpty) 'flow': flow,
    }..addAll(_v3Extra(d.extra));
    await _call('POST', '/panel/api/clients/add', json: {'client': client, 'inboundIds': ids});
  }

  /// Form extras for 3.x; a uuid is sent as both `id` and `uuid`.
  static Map<String, dynamic> _v3Extra(Map<String, dynamic> extra) {
    final out = Map<String, dynamic>.from(extra);
    final uuid = asStr(out['uuid']) ?? '';
    if (uuid.isNotEmpty) out['id'] = uuid;
    return out;
  }

  /// Older panels only know a subset of fields and store tgId as a string
  /// on some versions, so unknown/typed fields are left out.
  static Map<String, dynamic> _legacyExtra(Map<String, dynamic> extra) {
    const keep = {'subId', 'flow', 'security', 'reset', 'password'};
    final out = <String, dynamic>{
      for (final e in extra.entries)
        if (keep.contains(e.key) && e.value != null && '${e.value}'.isNotEmpty) e.key: e.value,
    };
    final uuid = asStr(extra['uuid']) ?? '';
    if (uuid.isNotEmpty) out['id'] = uuid;
    return out;
  }

  Future<void> _updateClient(PanelUser u, Map<String, dynamic> client) async {
    if (_prefix == null) await _fetchInbounds();
    await _call('POST', '$_prefix/updateClient/${_enc(_clientId(u))}', form: {
      'id': '${u.inboundId}',
      'settings': jsonEncode({
        'clients': [client]
      }),
    });
  }

  @override
  Future<void> updateUser(PanelUser u, UserDraft d) async {
    if (await _isV3()) {
      // The server replaces the whole row, so send every field back.
      final body = Map<String, dynamic>.from(u.raw)
        ..remove('traffic')
        ..remove('inboundIds')
        ..['email'] = d.name
        ..['totalGB'] = d.totalBytes
        ..['expiryTime'] = _expiryValue(d)
        ..['enable'] = d.enabled
        ..['limitIp'] = d.limitIp
        ..['comment'] = d.note
        ..addAll(_v3Extra(d.extra));
      await _call('POST', '/panel/api/clients/update/${_enc(u.name)}', json: body);
      // Attach / detach inbounds that changed in the form.
      if (d.inboundIds.isNotEmpty) {
        final before = asList(u.raw['inboundIds']).map(asInt).whereType<int>().toSet();
        final attach = d.inboundIds.difference(before).toList();
        final detach = before.difference(d.inboundIds).toList();
        final email = _enc(d.name);
        if (attach.isNotEmpty) {
          await _call('POST', '/panel/api/clients/$email/attach', json: {'inboundIds': attach});
        }
        if (detach.isNotEmpty) {
          await _call('POST', '/panel/api/clients/$email/detach', json: {'inboundIds': detach});
        }
      }
      return;
    }
    final client = Map<String, dynamic>.from(u.raw)
      ..['email'] = d.name
      ..['totalGB'] = d.totalBytes
      ..['expiryTime'] = _expiryValue(d)
      ..['enable'] = d.enabled
      ..['limitIp'] = d.limitIp
      ..['comment'] = d.note
      ..addAll(_legacyExtra(d.extra));
    await _updateClient(u, client);
  }

  @override
  Future<void> setEnabled(PanelUser u, bool enabled) async {
    if (await _isV3()) {
      await _call('POST', '/panel/api/clients/${enabled ? 'bulkEnable' : 'bulkDisable'}', json: {
        'emails': [u.name]
      });
      return;
    }
    final client = Map<String, dynamic>.from(u.raw)..['enable'] = enabled;
    await _updateClient(u, client);
  }

  @override
  Future<void> deleteUser(PanelUser u) async {
    if (await _isV3()) {
      await _call('POST', '/panel/api/clients/del/${_enc(u.name)}');
      return;
    }
    if (_prefix == null) await _fetchInbounds();
    await _call('POST', '$_prefix/${u.inboundId}/delClient/${_enc(_clientId(u))}');
  }

  @override
  Future<void> resetTraffic(PanelUser u) async {
    if (await _isV3()) {
      await _call('POST', '/panel/api/clients/resetTraffic/${_enc(u.name)}');
      return;
    }
    if (_prefix == null) await _fetchInbounds();
    await _call('POST', '$_prefix/${u.inboundId}/resetClientTraffic/${_enc(u.name)}');
  }

  @override
  Future<void> restartCore() async {
    for (final p in _restartCandidates) {
      try {
        await _call('POST', p);
        return;
      } on NotFoundException {
        continue;
      }
    }
    throw ApiException('Restart API not found on this panel.');
  }

  // ---------------------------------------------------------------- inbounds

  static const _jsonFields = ['settings', 'streamSettings', 'sniffing'];

  @override
  Future<Map<String, dynamic>> rawInbound(int id) async {
    final list = await _fetchInbounds();
    final ib = list.firstWhere((e) => asInt(e['id']) == id,
        orElse: () => throw ApiException('Inbound not found.'));
    // Deep copy with the JSON-string fields of older panels decoded.
    final copy = asMap(jsonDecode(jsonEncode(ib)));
    for (final k in _jsonFields) {
      copy[k] = asMap(copy[k]);
    }
    copy.remove('clientStats');
    return copy;
  }

  @override
  Future<void> saveInbound(Map<String, dynamic> inbound, {int? id}) async {
    if (_prefix == null) await _fetchInbounds();
    final v3 = await _isV3();
    final body = Map<String, dynamic>.from(inbound)..remove('clientStats');
    for (final k in _jsonFields) {
      final v = asMap(body[k]);
      // 3.x prefers objects; older panels store JSON strings.
      body[k] = v3 ? v : jsonEncode(v);
    }
    await _call('POST', id == null ? '$_prefix/add' : '$_prefix/update/$id', json: body);
    _rawInbounds = [];
  }

  @override
  Future<void> deleteInbound(int id) async {
    if (_prefix == null) await _fetchInbounds();
    await _call('POST', '$_prefix/del/$id');
    _rawInbounds = [];
  }

  @override
  Future<void> setInboundEnabled(int id, bool enabled) async {
    if (await _isV3()) {
      await _call('POST', '/panel/api/inbounds/setEnable/$id', json: {'enable': enabled});
      return;
    }
    final ib = await rawInbound(id);
    ib['enable'] = enabled;
    await saveInbound(ib, id: id);
  }

  @override
  Future<void> resetInboundTraffic(int id) async {
    if (await _isV3()) {
      await _call('POST', '/panel/api/inbounds/$id/resetTraffic');
      return;
    }
    if (_prefix == null) await _fetchInbounds();
    await _call('POST', '$_prefix/resetAllClientTraffics/$id');
  }

  @override
  Future<(String, String)> newRealityKeys() async {
    for (final c in const [
      ['GET', '/panel/api/server/getNewX25519Cert'],
      ['POST', '/server/getNewX25519Cert'],
      ['POST', '/panel/server/getNewX25519Cert'],
    ]) {
      try {
        final m = asMap(await _call(c[0], c[1]));
        return (asStr(m['privateKey']) ?? '', asStr(m['publicKey']) ?? '');
      } on NotFoundException {
        continue;
      }
    }
    throw ApiException('Key generation is not available on this panel.');
  }

  // ---------------------------------------------------------------- settings

  String? _settingPrefix;
  String? _xrayPrefix;

  static const _settingPrefixes = ['/panel/api/setting', '/panel/setting', '/xui/setting'];
  static const _xrayPrefixes = ['/panel/api/xray', '/panel/xray', '/xui/xray'];

  @override
  Future<Map<String, dynamic>> panelSettings() async {
    for (final p in _settingPrefix != null ? [_settingPrefix!] : _settingPrefixes) {
      try {
        final m = asMap(await _call('POST', '$p/all'));
        _settingPrefix = p;
        return m;
      } on NotFoundException {
        continue;
      }
    }
    throw ApiException('Settings API not found on this panel.');
  }

  @override
  Future<void> savePanelSettings(Map<String, dynamic> settings) async {
    if (_settingPrefix == null) await panelSettings();
    // Secrets that come back blank (redacted) are kept by the panel.
    await _call('POST', '$_settingPrefix/update', json: settings);
    _subTried = false;
  }

  @override
  Future<void> restartPanel() async {
    if (_settingPrefix == null) await panelSettings();
    await _call('POST', '$_settingPrefix/restartPanel');
  }

  @override
  Future<String> xrayConfig() async {
    for (final p in _xrayPrefix != null ? [_xrayPrefix!] : _xrayPrefixes) {
      try {
        final outer = asMap(await _call('POST', '$p/'));
        _xrayPrefix = p;
        final inner = outer['xraySetting'];
        final cfg = inner is String ? jsonDecode(inner) : inner;
        return const JsonEncoder.withIndent('  ').convert(cfg);
      } on NotFoundException {
        continue;
      }
    }
    throw ApiException('Xray settings API not found on this panel.');
  }

  @override
  Future<void> saveXrayConfig(String json) async {
    jsonDecode(json); // throws FormatException on invalid JSON
    if (_xrayPrefix == null) await xrayConfig();
    await _call('POST', '$_xrayPrefix/update', form: {'xraySetting': json});
  }

  @override
  void dispose() => _http.close();
}
