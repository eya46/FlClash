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
    required TailscaleProps tailscale,
  }) = _SetupParams;

  factory SetupParams.fromJson(Map<String, dynamic> json) =>
      _$SetupParamsFromJson(json);
}

@freezed
abstract class UpdateParams with _$UpdateParams {
  const factory UpdateParams({
    required Tun tun,
    @JsonKey(name: 'mixed-port') required int mixedPort,
    @JsonKey(name: 'allow-lan') required bool allowLan,
    @JsonKey(name: 'find-process-mode')
    required FindProcessMode findProcessMode,
    required Mode mode,
    @JsonKey(name: 'log-level') required LogLevel logLevel,
    required bool ipv6,
    @JsonKey(name: 'tcp-concurrent') required bool tcpConcurrent,
    @JsonKey(name: 'external-controller')
    required ExternalControllerStatus externalController,
    @JsonKey(name: 'unified-delay') required bool unifiedDelay,
    required TailscaleProps tailscale,
  }) = _UpdateParams;

  factory UpdateParams.fromJson(Map<String, dynamic> json) =>
      _$UpdateParamsFromJson(json);
}

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
  }) = _VpnOptions;

  factory VpnOptions.fromJson(Map<String, Object?> json) =>
      _$VpnOptionsFromJson(json);
}

class TailscaleState {
  final bool enable;
  final bool acceptRoutes;
  final String backendState;
  final String authUrl;
  final List<String> tailscaleIps;
  final List<String> routes;
  final List<String> disabledRoutes;
  final String tailnet;
  final String magicDnsSuffix;
  final String error;
  final int peerCount;
  final int onlinePeerCount;
  final String lastHandshake;
  final List<TailscalePeerInfo> peers;
  final List<TailscaleDerpInfo> derp;

  const TailscaleState({
    required this.enable,
    required this.acceptRoutes,
    required this.backendState,
    required this.authUrl,
    required this.tailscaleIps,
    required this.routes,
    required this.disabledRoutes,
    required this.tailnet,
    required this.magicDnsSuffix,
    required this.error,
    required this.peerCount,
    required this.onlinePeerCount,
    required this.lastHandshake,
    required this.peers,
    required this.derp,
  });

  factory TailscaleState.fromJson(Map<String, dynamic> json) {
    List<String> readList(String key) {
      return (json[key] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(growable: false);
    }

    final peersRaw = json['peers'] as List<dynamic>? ?? const [];
    final peers = peersRaw
        .whereType<Map>()
        .map((item) =>
            TailscalePeerInfo.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);

    final derpRaw = json['derp'] as List<dynamic>? ?? const [];
    final derp = derpRaw
        .whereType<Map>()
        .map((item) =>
            TailscaleDerpInfo.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);

    return TailscaleState(
      enable: json['enable'] as bool? ?? false,
      acceptRoutes: json['accept-routes'] as bool? ?? false,
      backendState: json['backend-state'] as String? ?? '',
      authUrl: json['auth-url'] as String? ?? '',
      tailscaleIps: readList('tailscale-ips'),
      routes: readList('routes'),
      disabledRoutes: readList('disabled-routes'),
      tailnet: json['tailnet'] as String? ?? '',
      magicDnsSuffix: json['magic-dns-suffix'] as String? ?? '',
      error: json['error'] as String? ?? '',
      peerCount: json['peer-count'] as int? ?? 0,
      onlinePeerCount: json['online-peer-count'] as int? ?? 0,
      lastHandshake: json['last-handshake'] as String? ?? '',
      peers: peers,
      derp: derp,
    );
  }
}

enum TailscalePeerConnectionType { direct, derp, idle, offline, unknown }

class TailscaleDerpInfo {
  final int regionId;
  final String regionCode;
  final String regionName;
  final List<String> nodes;
  final bool avoid;
  final bool custom;
  final bool preferred;
  final bool inUse;
  final int latencyMs;

  const TailscaleDerpInfo({
    required this.regionId,
    required this.regionCode,
    required this.regionName,
    required this.nodes,
    required this.avoid,
    required this.custom,
    required this.preferred,
    required this.inUse,
    required this.latencyMs,
  });

  factory TailscaleDerpInfo.fromJson(Map<String, dynamic> json) {
    final nodesRaw = json['nodes'] as List<dynamic>? ?? const [];
    return TailscaleDerpInfo(
      regionId: (json['region-id'] as num?)?.toInt() ?? 0,
      regionCode: json['region-code'] as String? ?? '',
      regionName: json['region-name'] as String? ?? '',
      nodes: nodesRaw.map((item) => item as String).toList(growable: false),
      avoid: json['avoid'] as bool? ?? false,
      custom: json['custom'] as bool? ?? false,
      preferred: json['preferred'] as bool? ?? false,
      inUse: json['in-use'] as bool? ?? false,
      latencyMs: (json['latency-ms'] as num?)?.toInt() ?? -1,
    );
  }
}

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

  String get displayName {
    if (hostName.isNotEmpty) return hostName;
    if (dnsName.isNotEmpty) return dnsName;
    if (tailscaleIps.isNotEmpty) return tailscaleIps.first;
    return 'peer';
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
abstract class UpdateGeoDataParams with _$UpdateGeoDataParams {
  const factory UpdateGeoDataParams({
    @JsonKey(name: 'geo-type') required String geoType,
    @JsonKey(name: 'geo-name') required String geoName,
  }) = _UpdateGeoDataParams;

  factory UpdateGeoDataParams.fromJson(Map<String, Object?> json) =>
      _$UpdateGeoDataParamsFromJson(json);
}

@freezed
abstract class CoreEvent with _$CoreEvent {
  const factory CoreEvent({required CoreEventType type, dynamic data}) =
      _CoreEvent;

  factory CoreEvent.fromJson(Map<String, Object?> json) =>
      _$CoreEventFromJson(json);
}

@freezed
abstract class InvokeMessage with _$InvokeMessage {
  const factory InvokeMessage({required InvokeMessageType type, dynamic data}) =
      _InvokeMessage;

  factory InvokeMessage.fromJson(Map<String, Object?> json) =>
      _$InvokeMessageFromJson(json);
}

@freezed
abstract class Delay with _$Delay {
  const factory Delay({required String name, required String url, int? value}) =
      _Delay;

  factory Delay.fromJson(Map<String, Object?> json) => _$DelayFromJson(json);
}

@freezed
abstract class Now with _$Now {
  const factory Now({required String name, required String value}) = _Now;

  factory Now.fromJson(Map<String, Object?> json) => _$NowFromJson(json);
}

@freezed
abstract class ProviderSubscriptionInfo with _$ProviderSubscriptionInfo {
  const factory ProviderSubscriptionInfo({
    @JsonKey(name: 'UPLOAD') @Default(0) int upload,
    @JsonKey(name: 'DOWNLOAD') @Default(0) int download,
    @JsonKey(name: 'TOTAL') @Default(0) int total,
    @JsonKey(name: 'EXPIRE') @Default(0) int expire,
  }) = _ProviderSubscriptionInfo;

  factory ProviderSubscriptionInfo.fromJson(Map<String, Object?> json) =>
      _$ProviderSubscriptionInfoFromJson(json);
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
abstract class Action with _$Action {
  const factory Action({
    required ActionMethod method,
    required dynamic data,
    required String id,
  }) = _Action;

  factory Action.fromJson(Map<String, Object?> json) => _$ActionFromJson(json);
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

@freezed
abstract class ActionResult with _$ActionResult {
  const factory ActionResult({
    required ActionMethod method,
    required dynamic data,
    String? id,
    @Default(ResultType.success) ResultType code,
  }) = _ActionResult;

  factory ActionResult.fromJson(Map<String, Object?> json) =>
      _$ActionResultFromJson(json);
}

extension ActionResultExt on ActionResult {
  Result get toResult {
    if (code == ResultType.success) {
      return Result.success(data);
    } else {
      return Result.error('$data');
    }
  }
}
