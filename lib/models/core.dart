import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/core.freezed.dart';
part 'generated/core.g.dart';

@freezed
abstract class SetupParams with _$SetupParams {
  const factory SetupParams({
    @JsonKey(name: 'selected-map') required Map<String, String> selectedMap,
    @JsonKey(name: 'test-url') required String testUrl,
    @Default(false) @JsonKey(name: 'skip-cert-verify') bool skipCertVerify,
    @JsonKey(includeIfNull: false) TailscaleAccountsSchema? tailscale,
    @JsonKey(includeIfNull: false) SetupBase? base,
  }) = _SetupParams;

  factory SetupParams.fromJson(Map<String, dynamic> json) =>
      _$SetupParamsFromJson(json);
}

@freezed
abstract class SetupBase with _$SetupBase {
  const factory SetupBase({required String path, required String overlay}) =
      _SetupBase;

  factory SetupBase.fromJson(Map<String, dynamic> json) =>
      _$SetupBaseFromJson(json);
}

@freezed
abstract class ProfileBase with _$ProfileBase {
  const factory ProfileBase({
    required Map<String, dynamic> config,
    required String digest,
    @Default([]) @JsonKey(name: 'match-rules') List<String> matchRules,
    @Default(0) int proxies,
    @Default(0) @JsonKey(name: 'proxy-groups') int proxyGroups,
    @Default(0) int rules,
  }) = _ProfileBase;

  factory ProfileBase.fromJson(Map<String, dynamic> json) =>
      _$ProfileBaseFromJson(json);
}

@freezed
abstract class UpdateParams with _$UpdateParams {
  const factory UpdateParams({
    @JsonKey(toJson: _tunCoreJson) required Tun tun,
    @JsonKey(name: 'mixed-port') required int mixedPort,
    @JsonKey(name: 'allow-lan') required bool allowLan,
    @JsonKey(name: 'find-process-mode')
    required FindProcessMode findProcessMode,
    required Mode mode,
    @JsonKey(name: 'log-level') required LogLevel logLevel,
    bool? ipv6,
    @JsonKey(name: 'tcp-concurrent') bool? tcpConcurrent,
    @JsonKey(name: 'external-controller')
    required ExternalControllerStatus externalController,
    @Default('') String secret,
    @JsonKey(name: 'unified-delay') bool? unifiedDelay,
    @Default([]) List<String> authentication,
    @Default(false) @JsonKey(name: 'geo-auto-update') bool geoAutoUpdate,
    @Default(24) @JsonKey(name: 'geo-update-interval') int geoUpdateInterval,
    @Default({}) @JsonKey(name: 'geox-url') Map<String, String> geoXUrl,
    @Default(false) @JsonKey(name: 'skip-cert-verify') bool skipCertVerify,
    @JsonKey(includeIfNull: false) TailscaleAccountsSchema? tailscale,
  }) = _UpdateParams;

  factory UpdateParams.fromJson(Map<String, dynamic> json) =>
      _$UpdateParamsFromJson(json);
}

Map<String, Object?> _tunCoreJson(Tun tun) => tun.coreJson;

@freezed
abstract class VpnOptions with _$VpnOptions {
  const factory VpnOptions({
    required bool enable,
    required int port,
    required bool ipv6,
    required bool dnsHijacking,
    required AccessControlProps accessControlProps,
    required bool allowBypass,
    required bool systemProxy,
    required List<String> bypassDomain,
    required String stack,
    @Default([]) List<String> routeAddress,
    @Default(0) int mtu,
    @Default('') String congestionController,
  }) = _VpnOptions;

  factory VpnOptions.fromJson(Map<String, Object?> json) =>
      _$VpnOptionsFromJson(json);
}

/// Account order is the user's order; the literal lists are sorted so an
/// unchanged model never triggers a replay.
@freezed
abstract class TailscaleAccountsSchema with _$TailscaleAccountsSchema {
  const factory TailscaleAccountsSchema({
    @JsonKey(name: 'legacy-alias') @Default(false) bool legacyAlias,
    @Default([]) List<TailscaleAccountSchema> accounts,
  }) = _TailscaleAccountsSchema;

  factory TailscaleAccountsSchema.fromJson(Map<String, dynamic> json) =>
      _$TailscaleAccountsSchemaFromJson(json);
}

@freezed
abstract class TailscaleAccountSchema with _$TailscaleAccountSchema {
  const factory TailscaleAccountSchema({
    @Default('') String id,
    @Default('') String label,
    @Default(true) bool enable,
    @JsonKey(name: 'state-dir') @Default('') String stateDir,
    @Default('') String hostname,
    @JsonKey(name: 'auth-key') @Default('') String authKey,
    @JsonKey(name: 'control-url') @Default('') String controlUrl,
    @Default(false) bool ephemeral,
    @Default(true) bool udp,
    @JsonKey(name: 'accept-routes') @Default(true) bool acceptRoutes,
    @JsonKey(name: 'exit-node') @Default('') String exitNode,
    @JsonKey(name: 'exit-node-allow-lan-access')
    @Default(false)
    bool exitNodeAllowLanAccess,
    @JsonKey(name: 'dialer-proxy') @Default('') String dialerProxy,
    @JsonKey(name: 'peer-cidrs') @Default([]) List<String> peerCidrs,
    @JsonKey(name: 'peer-domains') @Default([]) List<String> peerDomains,
    @JsonKey(name: 'route-cidrs') @Default([]) List<String> routeCidrs,
    @JsonKey(name: 'extra-rules') @Default([]) List<String> extraRules,
  }) = _TailscaleAccountSchema;

  factory TailscaleAccountSchema.fromJson(Map<String, dynamic> json) =>
      _$TailscaleAccountSchemaFromJson(json);
}

List<String> _sortedLiterals(Iterable<String> values) =>
    {...values}.toList()..sort();

extension TailscaleAccountPropsSchemaExt on TailscaleAccountProps {
  String get outboundName => 'TAILNET-${sanitizeTailscaleLabel(label)}';

  TailscaleAccountSchema get schema => TailscaleAccountSchema(
    id: id,
    label: label,
    enable: enable,
    stateDir: stateDir,
    hostname: hostname,
    authKey: authKey,
    controlUrl: controlUrl,
    ephemeral: ephemeral,
    udp: udp,
    acceptRoutes: acceptRoutes,
    exitNode: exitNode,
    exitNodeAllowLanAccess: exitNodeAllowLanAccess,
    dialerProxy: dialerProxy,
    peerCidrs: _sortedLiterals([
      for (final peer in peers)
        if (peer.enabled)
          for (final ip in peer.tailscaleIps)
            ip.contains(':') ? '$ip/128' : '$ip/32',
    ]),
    peerDomains: _sortedLiterals([
      for (final peer in peers)
        if (peer.enabled && peer.dnsName.isNotEmpty) peer.dnsName,
      if (magicDnsSuffix.isNotEmpty) magicDnsSuffix,
    ]),
    routeCidrs: _sortedLiterals([
      for (final route in routes)
        if (route.enabled) route.cidr,
    ]),
    extraRules: [...extraRules]..sort(),
  );
}

extension TailscaleAccountsSchemaExt on TailscaleAccounts {
  TailscaleAccountsSchema get schema => TailscaleAccountsSchema(
    legacyAlias: legacyAlias,
    accounts: [for (final account in accounts) account.schema],
  );

  /// Suffix -> that account's outbound; the first account wins a shared one.
  Map<String, String> get nameserverPolicy => {
    for (final account in accounts)
      if (account.enable && account.magicDnsSuffix.isNotEmpty)
        account.magicDnsSuffix: 'tailscale://${account.outboundName}',
  };

  /// What the Android VpnService route list and the private-bypass decision
  /// consume.
  List<String> get enabledRouteCidrs => _sortedLiterals([
    for (final account in accounts)
      if (account.enable)
        for (final route in account.routes)
          if (route.enabled) route.cidr,
  ]);

  bool get hasEnabledPrivateRoute =>
      enabledRouteCidrs.any(_touchesPrivateRoute);
}

const _privateV4RouteSpaces = ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'];

({BigInt start, BigInt end})? _cidrRange(String cidr) {
  final slash = cidr.indexOf('/');
  if (slash < 0) {
    return null;
  }
  final address = InternetAddress.tryParse(cidr.substring(0, slash).trim());
  if (address == null) {
    return null;
  }
  final bits = address.type == InternetAddressType.IPv4 ? 32 : 128;
  final prefix = int.tryParse(cidr.substring(slash + 1).trim());
  if (prefix == null || prefix < 0 || prefix > bits) {
    return null;
  }
  var value = BigInt.zero;
  for (final byte in address.rawAddress) {
    value = (value << 8) | BigInt.from(byte);
  }
  final hostBits = bits - prefix;
  final start = value >> hostBits << hostBits;
  return (start: start, end: start | ((BigInt.one << hostBits) - BigInt.one));
}

bool _touchesPrivateRoute(String cidr) {
  final range = _cidrRange(cidr);
  if (range == null) {
    return false;
  }
  return _privateV4RouteSpaces.any((space) {
    final other = _cidrRange(space)!;
    return range.start <= other.end && other.start <= range.end;
  });
}

class TailscaleAccountsState {
  final List<TailscaleAccountState> accounts;

  const TailscaleAccountsState({required this.accounts});

  factory TailscaleAccountsState.fromJson(Map<String, dynamic> json) {
    final raw = json['accounts'] as List<dynamic>? ?? const [];
    return TailscaleAccountsState(
      accounts: raw
          .whereType<Map>()
          .map(
            (item) =>
                TailscaleAccountState.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }
}

class TailscaleAccountState {
  final String id;
  final String name;
  final bool present;
  final String backendState;
  final String authUrl;
  final String tailnet;
  final String magicDnsSuffix;
  final List<String> tailscaleIps;
  final List<String> selfRoutes;
  final int peerCount;
  final int onlinePeerCount;
  final List<TailscalePeerInfo> peers;
  final String error;

  const TailscaleAccountState({
    required this.id,
    required this.name,
    required this.present,
    required this.backendState,
    required this.authUrl,
    required this.tailnet,
    required this.magicDnsSuffix,
    required this.tailscaleIps,
    required this.selfRoutes,
    required this.peerCount,
    required this.onlinePeerCount,
    required this.peers,
    required this.error,
  });

  /// Outside Running the snapshot carries no peer data worth merging.
  bool get isRunning => present && error.isEmpty && backendState == 'Running';

  factory TailscaleAccountState.fromJson(Map<String, dynamic> json) {
    List<String> readList(String key) {
      return (json[key] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(growable: false);
    }

    final peersRaw = json['peers'] as List<dynamic>? ?? const [];
    final peers = peersRaw
        .whereType<Map>()
        .map((item) => TailscalePeerInfo.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);

    return TailscaleAccountState(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      present: json['present'] as bool? ?? false,
      backendState: json['backend-state'] as String? ?? '',
      authUrl: json['auth-url'] as String? ?? '',
      tailnet: json['tailnet'] as String? ?? '',
      magicDnsSuffix: json['magic-dns-suffix'] as String? ?? '',
      tailscaleIps: readList('tailscale-ips'),
      selfRoutes: readList('self-routes'),
      peerCount: json['peer-count'] as int? ?? 0,
      onlinePeerCount: json['online-peer-count'] as int? ?? 0,
      peers: peers,
      error: json['error'] as String? ?? '',
    );
  }
}

enum TailscalePeerConnectionType { direct, derp, idle, offline, unknown }

class TailscalePeerInfo {
  final String hostName;
  final String dnsName;
  final List<String> tailscaleIps;
  final List<String> primaryRoutes;
  final bool online;
  final bool active;
  final bool exitNode;
  final bool exitNodeOption;
  final TailscalePeerConnectionType connectionType;
  final String curAddr;
  final String relay;
  final String lastHandshake;
  final int rxBytes;
  final int txBytes;

  const TailscalePeerInfo({
    required this.hostName,
    required this.dnsName,
    required this.tailscaleIps,
    required this.primaryRoutes,
    required this.online,
    required this.active,
    required this.exitNode,
    required this.exitNodeOption,
    required this.connectionType,
    required this.curAddr,
    required this.relay,
    required this.lastHandshake,
    required this.rxBytes,
    required this.txBytes,
  });

  /// The merge key: the normalized dns-name, or the first Tailscale IP.
  String get mergeKey {
    if (dnsName.isNotEmpty) return dnsName;
    if (tailscaleIps.isNotEmpty) return tailscaleIps.first;
    return '';
  }

  String get displayName {
    if (hostName.isNotEmpty) return hostName;
    if (dnsName.isNotEmpty) return dnsName;
    if (tailscaleIps.isNotEmpty) return tailscaleIps.first;
    return 'peer';
  }

  TailscalePeerEntry toEntry({required bool enabled}) {
    return TailscalePeerEntry(
      key: mergeKey,
      dnsName: dnsName,
      tailscaleIps: tailscaleIps,
      exitNodeOption: exitNodeOption,
      enabled: enabled,
    );
  }

  factory TailscalePeerInfo.fromJson(Map<String, dynamic> json) {
    List<String> readList(String key) {
      return (json[key] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(growable: false);
    }

    final typeRaw = (json['connection-type'] as String? ?? '').toLowerCase();
    final type = switch (typeRaw) {
      'direct' => TailscalePeerConnectionType.direct,
      'derp' => TailscalePeerConnectionType.derp,
      'idle' => TailscalePeerConnectionType.idle,
      'offline' => TailscalePeerConnectionType.offline,
      _ => TailscalePeerConnectionType.unknown,
    };

    return TailscalePeerInfo(
      hostName: json['host-name'] as String? ?? '',
      dnsName: json['dns-name'] as String? ?? '',
      tailscaleIps: readList('tailscale-ips'),
      primaryRoutes: readList('primary-routes'),
      online: json['online'] as bool? ?? false,
      active: json['active'] as bool? ?? false,
      exitNode: json['exit-node'] as bool? ?? false,
      exitNodeOption: json['exit-node-option'] as bool? ?? false,
      connectionType: type,
      curAddr: json['cur-addr'] as String? ?? '',
      relay: json['relay'] as String? ?? '',
      lastHandshake: json['last-handshake'] as String? ?? '',
      rxBytes: (json['rx-bytes'] as num?)?.toInt() ?? 0,
      txBytes: (json['tx-bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Keeps toggles, new entries arrive enabled, gone entries drop; outside
/// Running the model is untouched.
TailscaleAccountProps mergeTailscaleAccount(
  TailscaleAccountProps account,
  TailscaleAccountState? snapshot,
) {
  if (snapshot == null || !snapshot.isRunning) {
    return account;
  }
  final peersByKey = {for (final peer in account.peers) peer.key: peer};
  final routesByCidr = {for (final route in account.routes) route.cidr: route};
  return account.copyWith(
    magicDnsSuffix: snapshot.magicDnsSuffix,
    peers: [
      for (final peer in snapshot.peers)
        if (peer.mergeKey.isNotEmpty)
          peer.toEntry(enabled: peersByKey[peer.mergeKey]?.enabled ?? true),
    ],
    routes: [
      for (final cidr in _sortedLiterals(
        snapshot.peers.expand((peer) => peer.primaryRoutes),
      ))
        TailscaleRouteEntry(
          cidr: cidr,
          enabled: routesByCidr[cidr]?.enabled ?? true,
        ),
    ],
  );
}

extension VpnOptionsExt on VpnOptions {
  /// Only what `ServiceController.start` and `VpnService.handleStart` read.
  VpnOptions get effective {
    if (!enable) {
      return const VpnOptions(
        enable: false,
        port: 0,
        ipv6: false,
        dnsHijacking: false,
        accessControlProps: AccessControlProps(),
        allowBypass: false,
        systemProxy: false,
        bypassDomain: [],
        stack: '',
      );
    }
    final accessControl = accessControlProps;
    final accepts = accessControl.mode == AccessControlMode.acceptSelected;
    return copyWith(
      port: systemProxy ? port : 0,
      bypassDomain: systemProxy ? bypassDomain : const [],
      accessControlProps: accessControl.enable
          ? AccessControlProps(
              enable: true,
              mode: accessControl.mode,
              acceptList: accepts ? accessControl.acceptList : const [],
              rejectList: accepts ? const [] : accessControl.rejectList,
            )
          : const AccessControlProps(),
    );
  }
}

@freezed
abstract class InitParams with _$InitParams {
  const factory InitParams({
    @JsonKey(name: 'home-dir') required String homeDir,
    required int version,
  }) = _InitParams;

  factory InitParams.fromJson(Map<String, Object?> json) =>
      _$InitParamsFromJson(json);
}

@freezed
abstract class ChangeProxyParams with _$ChangeProxyParams {
  const factory ChangeProxyParams({
    @JsonKey(name: 'group-name') required String groupName,
    @JsonKey(name: 'proxy-name') required String proxyName,
  }) = _ChangeProxyParams;

  factory ChangeProxyParams.fromJson(Map<String, Object?> json) =>
      _$ChangeProxyParamsFromJson(json);
}

@freezed
abstract class ChangeProxyResult with _$ChangeProxyResult {
  const factory ChangeProxyResult({
    @Default('') String message,
    @Default(false) bool changed,
  }) = _ChangeProxyResult;

  factory ChangeProxyResult.fromJson(Map<String, Object?> json) =>
      _$ChangeProxyResultFromJson(json);
}

@freezed
abstract class RouteSnapshot with _$RouteSnapshot {
  const factory RouteSnapshot({
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
  }) = _RouteSnapshot;

  factory RouteSnapshot.fromJson(Map<String, Object?> json) =>
      _$RouteSnapshotFromJson(json);
}

/// [exit] is the Core's name for where a connection left, only compared whole.
@freezed
abstract class RouteHit with _$RouteHit {
  const factory RouteHit({
    @Default('') String host,
    @Default('') String proxy,
    @Default('') String exit,
  }) = _RouteHit;

  factory RouteHit.fromJson(Map<String, Object?> json) =>
      _$RouteHitFromJson(json);
}

@freezed
abstract class CheckRoutesParams with _$CheckRoutesParams {
  const factory CheckRoutesParams({@Default([]) List<List<RouteHit>> routes}) =
      _CheckRoutesParams;

  factory CheckRoutesParams.fromJson(Map<String, Object?> json) =>
      _$CheckRoutesParamsFromJson(json);
}

@freezed
abstract class RouteCheck with _$RouteCheck {
  const factory RouteCheck({
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<bool> held,
  }) = _RouteCheck;

  factory RouteCheck.fromJson(Map<String, Object?> json) =>
      _$RouteCheckFromJson(json);
}

@freezed
abstract class CoreEvent with _$CoreEvent {
  const factory CoreEvent({required CoreEventType type, dynamic data}) =
      _CoreEvent;

  factory CoreEvent.fromJson(Map<String, Object?> json) =>
      _$CoreEventFromJson(json);
}

@freezed
abstract class Delay with _$Delay {
  const factory Delay({required String name, required String url, int? value}) =
      _Delay;

  factory Delay.fromJson(Map<String, Object?> json) => _$DelayFromJson(json);
}

@freezed
abstract class ProbeParams with _$ProbeParams {
  const factory ProbeParams({
    required String url,
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default({}) Map<String, String> headers,
    required int timeout,
    @JsonKey(name: 'max-body') @Default(0) int maxBody,
  }) = _ProbeParams;

  factory ProbeParams.fromJson(Map<String, Object?> json) =>
      _$ProbeParamsFromJson(json);
}

@freezed
abstract class ProbeResult with _$ProbeResult {
  const factory ProbeResult({
    @JsonKey(name: 'status-code') @Default(0) int statusCode,
    @Default(0) int delay,
    @Default('') String body,
    @Default('') String url,
    @Default([]) List<String> chains,
    @Default('') String rule,
    @JsonKey(name: 'rule-payload') @Default('') String rulePayload,
    String? error,
    String? message,
  }) = _ProbeResult;

  factory ProbeResult.fromJson(Map<String, Object?> json) =>
      _$ProbeResultFromJson(json);
}

@freezed
abstract class OutboundIpParams with _$OutboundIpParams {
  const factory OutboundIpParams({
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default([]) List<String> urls,
    required int timeout,
  }) = _OutboundIpParams;

  factory OutboundIpParams.fromJson(Map<String, Object?> json) =>
      _$OutboundIpParamsFromJson(json);
}

@freezed
abstract class OutboundIpResult with _$OutboundIpResult {
  const factory OutboundIpResult({
    @Default('') String url,
    @Default('') String body,
    @Default(0) int delay,
    @Default([]) List<String> chains,
    String? error,
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<RouteHit> hits,
    @JsonKey(name: 'node-hits') @Default([]) List<RouteHit> nodeHits,
  }) = _OutboundIpResult;

  factory OutboundIpResult.fromJson(Map<String, Object?> json) =>
      _$OutboundIpResultFromJson(json);
}

@freezed
abstract class ServiceCheckParams with _$ServiceCheckParams {
  const factory ServiceCheckParams({
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default([]) List<String> names,
    required int timeout,
  }) = _ServiceCheckParams;

  factory ServiceCheckParams.fromJson(Map<String, Object?> json) =>
      _$ServiceCheckParamsFromJson(json);
}

@freezed
abstract class ServiceCheckItem with _$ServiceCheckItem {
  const factory ServiceCheckItem({
    @Default('') String name,
    @Default('') String status,
    @Default('') String region,
    @Default(0) int delay,
    @Default([]) List<String> chains,
    @JsonKey(name: 'checked-at') @Default(0) int checkedAt,
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<RouteHit> hits,
  }) = _ServiceCheckItem;

  factory ServiceCheckItem.fromJson(Map<String, Object?> json) =>
      _$ServiceCheckItemFromJson(json);
}

@freezed
abstract class CoreMemoryStats with _$CoreMemoryStats {
  const factory CoreMemoryStats({
    @Default(0) int rss,
    @Default(0) int heapInuse,
    @Default(0) int heapIdle,
    @Default(0) int stackInuse,
    @Default(0) int runtimeOther,
  }) = _CoreMemoryStats;

  factory CoreMemoryStats.fromJson(Map<String, Object?> json) =>
      _$CoreMemoryStatsFromJson(json);
}

extension CoreMemoryStatsExt on CoreMemoryStats {
  int get runtimeTotal => heapInuse + heapIdle + stackInuse + runtimeOther;
}

SubscriptionInfo? subscriptionInfoFormCore(Map<String, Object?>? json) {
  if (json == null) return null;
  return SubscriptionInfo(
    upload: (json['Upload'] as num?)?.toInt() ?? 0,
    download: (json['Download'] as num?)?.toInt() ?? 0,
    total: (json['Total'] as num?)?.toInt() ?? 0,
    expire: (json['Expire'] as num?)?.toInt() ?? 0,
  );
}

@freezed
abstract class ExternalProvider with _$ExternalProvider {
  const factory ExternalProvider({
    required String name,
    required String type,
    String? path,
    required int count,
    @JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore)
    SubscriptionInfo? subscriptionInfo,
    @JsonKey(name: 'vehicle-type') required String vehicleType,
    @JsonKey(name: 'update-at') required DateTime updateAt,
  }) = _ExternalProvider;

  factory ExternalProvider.fromJson(Map<String, Object?> json) =>
      _$ExternalProviderFromJson(json);
}

extension ExternalProviderExt on ExternalProvider {
  String get updatingKey => 'provider_$name';
}

@freezed
abstract class ProxiesData with _$ProxiesData {
  const factory ProxiesData({
    required Map<String, dynamic> proxies,
    required List<String> all,
  }) = _ProxiesData;

  factory ProxiesData.fromJson(Map<String, Object?> json) =>
      _$ProxiesDataFromJson(json);
}
