export 'panel_config.dart';

enum UserStatus { active, disabled, expired, limited, onHold }

class ServerStats {
  const ServerStats({
    this.cpu,
    this.cpuCores,
    this.memUsed,
    this.memTotal,
    this.diskUsed,
    this.diskTotal,
    this.swapUsed,
    this.swapTotal,
    this.uptime,
    this.loads = const [],
    this.netUpSpeed,
    this.netDownSpeed,
    this.netSent,
    this.netRecv,
    this.coreState,
    this.coreVersion,
    this.coreError,
    this.tcpCount,
    this.udpCount,
    this.ipv4,
    this.ipv6,
    this.panelVersion,
    this.totalUsers,
    this.activeUsers,
    this.onlineUsers,
    this.disabledUsers,
    this.expiredUsers,
    this.limitedUsers,
    this.onHoldUsers,
  });

  final double? cpu; // percent
  final int? cpuCores;
  final int? memUsed, memTotal, diskUsed, diskTotal, swapUsed, swapTotal;
  final int? uptime; // seconds
  final List<double> loads;
  final int? netUpSpeed, netDownSpeed; // bytes/s
  final int? netSent, netRecv; // bytes
  final String? coreState, coreVersion, coreError;
  final int? tcpCount, udpCount;
  final String? ipv4, ipv6;
  final String? panelVersion;
  final int? totalUsers, activeUsers, onlineUsers, disabledUsers;
  final int? expiredUsers, limitedUsers, onHoldUsers;

  bool get coreRunning => coreState == 'running';
}

class PanelUser {
  const PanelUser({
    required this.key,
    required this.name,
    required this.enabled,
    required this.status,
    this.up = 0,
    this.down = 0,
    this.total = 0,
    this.expiry,
    this.expiryDaysAfterFirstUse,
    this.online = false,
    this.lastOnline,
    this.subUrl,
    this.links = const [],
    this.note,
    this.limitIp,
    this.inboundId,
    this.inboundName,
    this.protocol,
    this.raw = const {},
  });

  /// Unique within a panel.
  final String key;

  /// x-ui: client email, Marzban: username.
  final String name;
  final bool enabled;
  final UserStatus status;
  final int up, down; // bytes
  final int total; // bytes, 0 = unlimited
  final DateTime? expiry;

  /// Expiry that starts counting on first connection (x-ui negative expiry,
  /// Marzban on_hold).
  final int? expiryDaysAfterFirstUse;
  final bool online;
  final DateTime? lastOnline;
  final String? subUrl;
  final List<String> links;
  final String? note;
  final int? limitIp;
  final int? inboundId;
  final String? inboundName;
  final String? protocol;
  final Map<String, dynamic> raw;

  int get used => up + down;

  double? get usage =>
      total > 0 ? (used / total).clamp(0.0, 1.0).toDouble() : null;
}

class UserSummary {
  const UserSummary({
    required this.total,
    required this.active,
    required this.online,
    required this.disabled,
    required this.expired,
    required this.limited,
    this.onHold = 0,
  });

  final int total, active, online, disabled, expired, limited, onHold;

  factory UserSummary.fromUsers(List<PanelUser> users) {
    int c(UserStatus s) => users.where((u) => u.status == s).length;
    return UserSummary(
      total: users.length,
      active: c(UserStatus.active),
      online: users.where((u) => u.online).length,
      disabled: c(UserStatus.disabled),
      expired: c(UserStatus.expired),
      limited: c(UserStatus.limited),
      onHold: c(UserStatus.onHold),
    );
  }

  static UserSummary? fromStats(ServerStats s) => s.totalUsers == null
      ? null
      : UserSummary(
          total: s.totalUsers ?? 0,
          active: s.activeUsers ?? 0,
          online: s.onlineUsers ?? 0,
          disabled: s.disabledUsers ?? 0,
          expired: s.expiredUsers ?? 0,
          limited: s.limitedUsers ?? 0,
          onHold: s.onHoldUsers ?? 0,
        );
}

class InboundInfo {
  const InboundInfo({
    this.id,
    required this.tag,
    required this.remark,
    required this.protocol,
    this.port,
    this.network,
    this.security,
    this.enabled = true,
    this.up,
    this.down,
    this.total,
    this.clientCount,
    this.expiry,
  });

  final int? id;
  final String tag;
  final String remark;
  final String protocol;
  final int? port;
  final String? network;
  final String? security;
  final bool enabled;
  final int? up, down, total;
  final int? clientCount;
  final DateTime? expiry;

  String get title => remark.isNotEmpty ? remark : tag;
}

/// Values from the create/edit user form.
class UserDraft {
  UserDraft({
    required this.name,
    this.totalBytes = 0,
    this.expiry,
    this.expiryDaysAfterFirstUse,
    this.enabled = true,
    this.limitIp = 0,
    this.note = '',
    this.inboundId,
    this.inboundIds = const {},
    this.protocols = const {},
    this.flow = '',
    this.extra = const {},
  });

  final String name;
  final int totalBytes;
  final DateTime? expiry;
  final int? expiryDaysAfterFirstUse;
  final bool enabled;
  final int limitIp;
  final String note;

  /// x-ui: inbound to add the client to.
  final int? inboundId;

  /// 3X-UI 3.x: inbounds to attach the new client to.
  final Set<int> inboundIds;

  /// Marzban: protocols to enable.
  final Set<String> protocols;

  /// Marzban VLESS flow.
  final String flow;

  /// x-ui: extra client fields copied as-is into the client payload
  /// (limitHwid, tgId, subId, id/uuid, password, flow, security, group,
  /// reset, resetDay, resetMax, trafficReset, trafficResetDay).
  final Map<String, dynamic> extra;
}
