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
      ListItem(
        leading: Icon(_statusIcon(tailscaleState), color: color),
        title: Text(
          _backendStateLabel(tailscaleState.backendState),
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        subtitle: tailscaleState.peerCount > 0
            ? Text(
                '${tailscaleState.onlinePeerCount}/${tailscaleState.peerCount} peers online'
                '${tailscaleState.lastHandshake.isNotEmpty ? '  ·  Last activity: ${_formatRelativeTime(tailscaleState.lastHandshake)}' : ''}',
              )
            : Text(tailscaleState.backendState),
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
          return ListItem.checkbox(
            title: Text(route),
            subtitle: Text(
              enabled
                  ? 'Handled by tsnet when matched.'
                  : 'Excluded from tsnet matching.',
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
        items: _buildRouteItems(_tailscaleState, tailscaleProps),
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
