import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/config/network.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

String _backendStateLabel(String state) {
  return switch (state) {
    'Running' => 'Connected',
    'Starting' => 'Connecting...',
    'Stopped' => 'Stopped',
    'NeedsLogin' => 'Login Required',
    'NeedsMachineAuth' => 'Awaiting Approval',
    'NoState' => 'Not Initialized',
    _ => state.isEmpty ? 'Unknown' : state,
  };
}

Color _statusColor(TailscaleState? state) {
  if (state == null) return Colors.grey;
  if (state.error.isNotEmpty) return Colors.red;
  return switch (state.backendState) {
    'Running' when state.onlinePeerCount > 0 => Colors.green,
    'Running' => Colors.amber,
    'Starting' => Colors.blue,
    'NeedsLogin' || 'NeedsMachineAuth' => Colors.orange,
    _ => Colors.grey,
  };
}

IconData _statusIcon(TailscaleState? state) {
  if (state == null) return Icons.help_outline;
  if (state.error.isNotEmpty) return Icons.error;
  return switch (state.backendState) {
    'Running' when state.onlinePeerCount > 0 => Icons.check_circle,
    'Running' => Icons.warning_amber_rounded,
    'Starting' => Icons.sync,
    'NeedsLogin' || 'NeedsMachineAuth' => Icons.login,
    'Stopped' => Icons.stop_circle_outlined,
    _ => Icons.help_outline,
  };
}

String? _healthHint(TailscaleState state) {
  if (state.error.isNotEmpty) return null;
  if (state.backendState == 'NeedsLogin') {
    return 'Complete sign-in below to connect to your Tailnet.';
  }
  if (state.backendState == 'NeedsMachineAuth') {
    return 'A Tailnet admin needs to approve this device.';
  }
  if (state.backendState == 'Running') {
    if (state.peerCount == 0) {
      return 'No peers found. Ensure other devices are connected to your Tailnet.';
    }
    if (state.onlinePeerCount == 0) {
      return 'All peers appear offline. Check Tailscale on your other devices.';
    }
    if (state.routes.isEmpty) {
      return 'Connected but no subnet routes found. Enable subnet routes in your Tailscale admin console.';
    }
    if (Platform.isAndroid) {
      return 'Android VPN mode may limit tsnet connectivity. '
          'If internal IPs are unreachable, try using a desktop device as the primary Tailscale node.';
    }
  }
  return null;
}

String _formatRelativeTime(String isoTime) {
  if (isoTime.isEmpty) return 'Never';
  final time = DateTime.tryParse(isoTime);
  if (time == null) return isoTime;
  final diff = DateTime.now().toUtc().difference(time);
  if (diff.isNegative) return 'Just now';
  if (diff.inSeconds < 10) return 'Just now';
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final formatted = value >= 10 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[unit]}';
}

({String label, Color color, IconData icon}) _peerConnectionBadge(
  TailscalePeerInfo peer,
) {
  switch (peer.connectionType) {
    case TailscalePeerConnectionType.direct:
      return (
        label: peer.curAddr.isNotEmpty ? 'Direct · ${peer.curAddr}' : 'Direct',
        color: Colors.green,
        icon: Icons.flash_on,
      );
    case TailscalePeerConnectionType.derp:
      return (
        label: peer.relay.isNotEmpty ? 'DERP · ${peer.relay}' : 'DERP relay',
        color: Colors.blue,
        icon: Icons.cloud_outlined,
      );
    case TailscalePeerConnectionType.idle:
      return (
        label: 'Idle (no path yet)',
        color: Colors.amber.shade700,
        icon: Icons.hourglass_empty,
      );
    case TailscalePeerConnectionType.offline:
      return (
        label: 'Offline',
        color: Colors.grey,
        icon: Icons.cloud_off_outlined,
      );
    case TailscalePeerConnectionType.unknown:
      return (
        label: 'Unknown',
        color: Colors.grey,
        icon: Icons.help_outline,
      );
  }
}

class TailscaleView extends ConsumerStatefulWidget {
  const TailscaleView({super.key});

  @override
  ConsumerState<TailscaleView> createState() => _TailscaleViewState();
}

class _TailscaleViewState extends ConsumerState<TailscaleView> {
  TailscaleState? _tailscaleState;
  Timer? _timer;
  bool _isLoading = true;
  bool _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refresh(silent: true);
    });
    ref.listenManual(tailscaleSettingProvider, (prev, next) {
      if (prev != next) {
        _refresh(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    final tailscaleState = await coreController.getTailscaleState();
    if (!mounted) {
      return;
    }
    setState(() {
      _tailscaleState = tailscaleState;
      _isLoading = false;
    });
  }

  Future<void> _reconnect() async {
    if (_isReconnecting) return;
    setState(() {
      _isReconnecting = true;
    });
    try {
      final error = await coreController.reconnectTailscale();
      if (!mounted) return;
      if (error.isNotEmpty) {
        context.showNotifier('Reconnect failed: $error');
      }
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _isReconnecting = false;
        });
      }
    }
  }

  Future<void> _openAuthUrl(String authUrl) async {
    final uri = Uri.tryParse(authUrl);
    if (uri == null) {
      context.showNotifier('Invalid Tailscale auth URL');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) {
      return;
    }
    if (!launched) {
      context.showNotifier('Failed to open Tailscale auth URL');
    }
  }

  void _toggleRoute({
    required TailscaleProps tailscaleProps,
    required String route,
    required bool enabled,
  }) {
    final disabledRoutes = Set<String>.from(tailscaleProps.disabledRoutes);
    if (enabled) {
      disabledRoutes.remove(route);
    } else {
      disabledRoutes.add(route);
    }
    final sortedRoutes = disabledRoutes.toList()..sort();
    ref
        .read(tailscaleSettingProvider.notifier)
        .update((state) => state.copyWith(disabledRoutes: sortedRoutes));
  }

  List<Widget> _buildStatusItems(TailscaleState? tailscaleState) {
    if (tailscaleState == null) {
      return [
        ListItem(
          leading: const Icon(Icons.info_outline),
          title: const Text('Status'),
          subtitle: const Text('Waiting for Tailscale state...'),
        ),
      ];
    }

    final color = _statusColor(tailscaleState);
    final statusItems = <Widget>[
      ListItem.open(
        leading: Icon(_statusIcon(tailscaleState), color: color),
        title: Text(
          _backendStateLabel(tailscaleState.backendState),
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        subtitle: tailscaleState.peerCount > 0
            ? Text(
                '${tailscaleState.onlinePeerCount}/${tailscaleState.peerCount} peers online'
                '${tailscaleState.lastHandshake.isNotEmpty ? '  ·  Last activity: ${_formatRelativeTime(tailscaleState.lastHandshake)}' : ''}'
                '  ·  Tap for details',
              )
            : const Text('Tap to view connection details'),
        trailing: const Icon(Icons.chevron_right),
        delegate: const OpenDelegate(widget: TailscaleStatusView()),
      ),
    ];

    final hint = _healthHint(tailscaleState);
    if (hint != null) {
      statusItems.add(
        ListItem(
          leading: Icon(
            Icons.tips_and_updates_outlined,
            color: Colors.amber.shade700,
          ),
          title: const Text('Hint'),
          subtitle: Text(hint),
        ),
      );
    }

    if (tailscaleState.error.isNotEmpty) {
      statusItems.add(
        ListItem(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: const Text('Error'),
          subtitle: Text(tailscaleState.error),
        ),
      );
    }

    if (tailscaleState.tailnet.isNotEmpty) {
      statusItems.add(
        ListItem(
          leading: const Icon(Icons.account_tree_outlined),
          title: const Text('Tailnet'),
          subtitle: Text(tailscaleState.tailnet),
        ),
      );
    }

    final tailscaleIps = tailscaleState.tailscaleIps.join(', ');
    if (tailscaleIps.isNotEmpty) {
      statusItems.add(
        ListItem(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Tailscale IPs'),
          subtitle: Text(tailscaleIps),
        ),
      );
    }

    if (tailscaleState.magicDnsSuffix.isNotEmpty) {
      statusItems.add(
        ListItem(
          leading: const Icon(Icons.domain_outlined),
          title: const Text('Magic DNS Suffix'),
          subtitle: Text(tailscaleState.magicDnsSuffix),
        ),
      );
    }

    if (tailscaleState.authUrl.isNotEmpty) {
      statusItems.add(
        ListItem(
          leading: const Icon(Icons.login, color: Colors.orange),
          title: const Text('Complete Sign-In'),
          subtitle: Text(tailscaleState.authUrl),
          trailing: const Icon(Icons.launch),
          onTap: () {
            _openAuthUrl(tailscaleState.authUrl);
          },
        ),
      );
    }

    return statusItems;
  }

  List<Widget> _buildRouteItems(
    TailscaleState? tailscaleState,
    TailscaleProps tailscaleProps,
    Set<String> appliedVpnRoutes,
  ) {
    final routes = tailscaleState?.routes ?? const <String>[];
    if (routes.isEmpty) {
      return [
        ListItem(
          leading: const Icon(Icons.route_outlined),
          title: const Text('Advertised Routes'),
          subtitle: const Text(
            'No subnet routes have been reported by Tailscale yet.',
          ),
        ),
      ];
    }

    final disabledRoutes = Set<String>.from(tailscaleProps.disabledRoutes);
    return routes
        .map((route) {
          final enabled = !disabledRoutes.contains(route);
          final pending = Platform.isAndroid &&
              isTailscaleSubnetNeedingVpnRoute(route) &&
              !appliedVpnRoutes.contains(route);
          final baseSubtitle = enabled
              ? 'Handled by tsnet when matched.'
              : 'Excluded from tsnet matching.';
          return ListItem.checkbox(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(route)),
                if (pending) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Pending VPN restart',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              pending
                  ? '$baseSubtitle Toggle the VPN off/on so Android picks '
                      'up this subnet.'
                  : baseSubtitle,
            ),
            delegate: CheckboxDelegate(
              value: enabled,
              onChanged: (value) {
                _toggleRoute(
                  tailscaleProps: tailscaleProps,
                  route: route,
                  enabled: value ?? false,
                );
              },
            ),
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final tailscaleProps = ref.watch(tailscaleSettingProvider);
    final appliedVpnRoutes =
        ref.watch(tailscaleRuntimeRoutesProvider).toSet();
    final isEnabled = tailscaleProps.enable;

    final items = <Widget>[
      ...generateSection(
        title: 'Connection',
        items: const [TailscaleEnableItem(), TailscaleAcceptRoutesItem()],
      ),
      ...generateSection(
        title: 'Authentication',
        items: const [
          TailscaleHostnameItem(),
          TailscaleAuthKeyItem(),
          TailscaleControlUrlItem(),
        ],
      ),
      ...generateSection(
        title: 'Status',
        items: _buildStatusItems(_tailscaleState),
      ),
      ...generateSection(
        title: 'Advertised Routes',
        items: _buildRouteItems(
          _tailscaleState,
          tailscaleProps,
          appliedVpnRoutes,
        ),
      ),
      ...generateSection(
        title: 'Routing',
        items: const [
          TailscaleRouteControlPlaneViaProxyItem(),
          TailscaleRouteDerpViaProxyItem(),
        ],
      ),
    ];

    return CommonScaffold(
      title: 'Tailscale',
      isLoading: _isLoading && _tailscaleState == null,
      actions: [
        if (isEnabled)
          _isReconnecting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: _reconnect,
                  tooltip: 'Reconnect',
                  icon: const Icon(Icons.refresh),
                ),
        IconButton(
          onPressed: () {
            _refresh();
          },
          tooltip: 'Refresh',
          icon: const Icon(Icons.sync),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: generateListView(items),
      ),
    );
  }
}

class TailscaleStatusView extends StatefulWidget {
  const TailscaleStatusView({super.key});

  @override
  State<TailscaleStatusView> createState() => _TailscaleStatusViewState();
}

class _TailscaleStatusViewState extends State<TailscaleStatusView> {
  TailscaleState? _tailscaleState;
  Timer? _timer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    final state = await coreController.getTailscaleState();
    if (!mounted) return;
    setState(() {
      _tailscaleState = state;
      _isLoading = false;
    });
  }

  List<Widget> _buildPeerItems(TailscaleState? tailscaleState) {
    final peers = tailscaleState?.peers ?? const <TailscalePeerInfo>[];
    if (peers.isEmpty) {
      return [
        ListItem(
          leading: const Icon(Icons.devices_other_outlined),
          title: const Text('Peers'),
          subtitle: const Text('No peers reported by Tailscale yet.'),
        ),
      ];
    }

    return peers.map((peer) {
      final badge = _peerConnectionBadge(peer);
      final details = <Widget>[];
      if (peer.tailscaleIps.isNotEmpty) {
        details.add(
          Text(
            peer.tailscaleIps.join(', '),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
      }
      if (peer.primaryRoutes.isNotEmpty) {
        details.add(
          Text('Routes: ${peer.primaryRoutes.join(', ')}'),
        );
      }
      if (peer.exitNode) {
        details.add(
          const Text(
            'Exit node · in use',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
        );
      } else if (peer.exitNodeOption) {
        details.add(const Text('Advertises exit-node option'));
      }
      final metaParts = <String>[];
      if (peer.lastHandshake.isNotEmpty) {
        metaParts.add('Handshake ${_formatRelativeTime(peer.lastHandshake)}');
      }
      if (peer.rxBytes > 0 || peer.txBytes > 0) {
        metaParts.add(
          'Rx ${_formatBytes(peer.rxBytes)} · Tx ${_formatBytes(peer.txBytes)}',
        );
      }
      if (metaParts.isNotEmpty) {
        details.add(Text(metaParts.join('  ·  ')));
      }

      final subtitle = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badge.icon, size: 14, color: badge.color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    badge.label,
                    style: TextStyle(
                      color: badge.color,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          ...details,
        ],
      );

      return ListItem(
        leading: Icon(
          peer.online ? Icons.computer : Icons.desktop_access_disabled,
          color: peer.online ? badge.color : Colors.grey,
        ),
        title: Text(
          peer.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle,
      );
    }).toList(growable: false);
  }

  List<Widget> _buildDerpItems(TailscaleState? tailscaleState) {
    final regions = tailscaleState?.derp ?? const <TailscaleDerpInfo>[];
    if (regions.isEmpty) {
      return [
        ListItem(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('DERP regions'),
          subtitle: const Text(
            'DERP map unavailable. Latency appears after a region has been probed.',
          ),
        ),
      ];
    }

    final sorted = [...regions]..sort((a, b) {
      if (a.preferred != b.preferred) return a.preferred ? -1 : 1;
      if (a.inUse != b.inUse) return a.inUse ? -1 : 1;
      if (a.custom != b.custom) return a.custom ? 1 : -1;
      final la = a.latencyMs;
      final lb = b.latencyMs;
      if (la >= 0 && lb >= 0 && la != lb) return la.compareTo(lb);
      if (la < 0 && lb >= 0) return 1;
      if (lb < 0 && la >= 0) return -1;
      return a.regionId.compareTo(b.regionId);
    });

    return sorted.map((region) {
      final latency = region.latencyMs;
      final (latencyLabel, latencyColor) = _derpLatencyLabel(latency);

      final tags = <Widget>[];
      if (region.preferred) {
        tags.add(_derpTag('Preferred', Colors.green));
      }
      if (region.inUse) {
        tags.add(_derpTag('In use', Colors.blue));
      }
      if (region.custom) {
        tags.add(_derpTag('Custom', Colors.deepPurple));
      }
      if (region.avoid) {
        tags.add(_derpTag('Avoid', Colors.grey));
      }

      final titleText = region.regionName.isNotEmpty
          ? '${region.regionCode.toUpperCase()} · ${region.regionName}'
          : region.regionCode.toUpperCase().isNotEmpty
              ? region.regionCode.toUpperCase()
              : '#${region.regionId}';

      final subtitleChildren = <Widget>[];
      if (tags.isNotEmpty) {
        subtitleChildren.add(
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Wrap(spacing: 6, runSpacing: 4, children: tags),
          ),
        );
      }
      if (region.nodes.isNotEmpty) {
        subtitleChildren.add(Text(region.nodes.join(', ')));
      }

      return ListItem(
        leading: Icon(
          region.preferred
              ? Icons.star
              : region.custom
                  ? Icons.dns_outlined
                  : Icons.cloud_outlined,
          color: region.preferred
              ? Colors.amber.shade700
              : region.inUse
                  ? Colors.blue
                  : null,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Text(
                titleText,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              latencyLabel,
              style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: latencyColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        subtitle: subtitleChildren.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: subtitleChildren,
              ),
      );
    }).toList(growable: false);
  }

  (String, Color?) _derpLatencyLabel(int ms) {
    if (ms < 0) return ('—', Colors.grey);
    if (ms < 60) return ('$ms ms', Colors.green);
    if (ms < 150) return ('$ms ms', Colors.lightGreen);
    if (ms < 300) return ('$ms ms', Colors.amber.shade700);
    return ('$ms ms', Colors.red);
  }

  Widget _derpTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _tailscaleState;
    final items = <Widget>[
      ...generateSection(
        title: 'Peers',
        items: _buildPeerItems(state),
      ),
      ...generateSection(
        title: 'DERP relays',
        items: _buildDerpItems(state),
      ),
    ];

    return CommonScaffold(
      title: 'Connection status',
      isLoading: _isLoading && state == null,
      actions: [
        IconButton(
          onPressed: () => _refresh(),
          tooltip: 'Refresh',
          icon: const Icon(Icons.sync),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: generateListView(items),
      ),
    );
  }
}
