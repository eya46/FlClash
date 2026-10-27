import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

const _stubBuildError = 'tailscale not available in this build';

TailscaleAccountProps? _accountOf(TailscaleAccounts accounts, String id) {
  for (final account in accounts.accounts) {
    if (account.id == id) {
      return account;
    }
  }
  return null;
}

TailscaleAccountState? _stateOf(TailscaleAccountsState? snapshot, String id) {
  for (final entry in snapshot?.accounts ?? const <TailscaleAccountState>[]) {
    if (entry.id == id) {
      return entry;
    }
  }
  return null;
}

String _backendStateLabel(AppLocalizations appLocalizations, String state) {
  return switch (state) {
    'Running' => appLocalizations.tailscaleRunning,
    'Starting' => appLocalizations.tailscaleStarting,
    'Stopped' => appLocalizations.tailscaleStopped,
    'NeedsLogin' => appLocalizations.tailscaleNeedsLogin,
    'NeedsMachineAuth' => appLocalizations.tailscaleWaitingApproval,
    'NoState' => appLocalizations.tailscaleNoState,
    _ => appLocalizations.unknown,
  };
}

String _accountStateLabel(
  AppLocalizations appLocalizations,
  TailscaleAccountProps account,
  TailscaleAccountState? state,
) {
  if (!account.enable) {
    return appLocalizations.disabled;
  }
  if (state == null || !state.present) {
    return appLocalizations.tailscaleInactive;
  }
  return _backendStateLabel(appLocalizations, state.backendState);
}

({Color color, Glyph glyph}) _accountStatusMarks(
  ColorScheme colorScheme,
  TailscaleAccountProps account,
  TailscaleAccountState? state,
) {
  if (!account.enable) {
    return (color: colorScheme.onSurfaceVariant, glyph: AppGlyphs.block);
  }
  if (state == null || !state.present) {
    return (color: colorScheme.onSurfaceVariant, glyph: AppGlyphs.vpn);
  }
  if (state.error.isNotEmpty) {
    return (color: colorScheme.error, glyph: AppGlyphs.error);
  }
  return switch (state.backendState) {
    'Running' when state.onlinePeerCount > 0 => (
      color: colorScheme.success,
      glyph: AppGlyphs.verified,
    ),
    'Running' => (color: colorScheme.success, glyph: AppGlyphs.checkCircle),
    'Starting' => (color: colorScheme.primary, glyph: AppGlyphs.sync),
    'NeedsLogin' ||
    'NeedsMachineAuth' => (color: colorScheme.warning, glyph: AppGlyphs.key),
    _ => (color: colorScheme.onSurfaceVariant, glyph: AppGlyphs.block),
  };
}

String _accountDisplayName(TailscaleAccountProps account) {
  return account.label.isEmpty ? account.outboundName : account.label;
}

String _peerEntryTitle(TailscalePeerEntry peer) {
  if (peer.dnsName.isNotEmpty) {
    return peer.dnsName;
  }
  if (peer.tailscaleIps.isNotEmpty) {
    return peer.tailscaleIps.first;
  }
  return peer.key;
}

String? _relativeTime(BuildContext context, String isoTime) {
  if (isoTime.isEmpty) {
    return null;
  }
  final time = DateTime.tryParse(isoTime);
  if (time == null) {
    return null;
  }
  return time.toLocal().getLastUpdateTimeDesc(context);
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

class TailscaleView extends ConsumerStatefulWidget {
  const TailscaleView({super.key});

  @override
  ConsumerState<TailscaleView> createState() => _TailscaleViewState();
}

class _TailscaleViewState extends ConsumerState<TailscaleView> {
  bool _applying = false;

  Future<void> _handleAddOrUpdate([TailscaleAccountProps? account]) async {
    final accounts = ref.read(tailscaleAccountsProvider);
    final result = await showFormSheet<TailscaleAccountProps>(
      context: context,
      builder: (_) => _AccountForm(
        account: account,
        otherAccounts: [
          for (final item in accounts.accounts)
            if (item.id != account?.id) item,
        ],
      ),
    );
    if (result == null) {
      return;
    }
    ref.read(tailscaleAccountsProvider.notifier).update((state) {
      return state.copyWith(
        accounts: account == null
            ? [...state.accounts, result]
            : [
                for (final item in state.accounts)
                  item.id == account.id ? result : item,
              ],
      );
    });
  }

  Widget _accountRow(
    AppLocalizations appLocalizations,
    TailscaleAccountProps account,
    TailscaleAccountsState? snapshot,
  ) {
    final state = _stateOf(snapshot, account.id);
    final marks = _accountStatusMarks(context.colorScheme, account, state);
    final subtitleParts = <String>[
      account.outboundName,
      _accountStateLabel(appLocalizations, account, state),
      if (state != null &&
          state.present &&
          state.backendState == 'Running' &&
          state.peerCount > 0)
        appLocalizations.tailscaleOnlinePeerCount(
          state.onlinePeerCount,
          state.peerCount,
        ),
    ];
    return ListItem.open(
      key: ValueKey(account.id),
      leading: GlyphIcon(marks.glyph, color: marks.color),
      title: Text(_accountDisplayName(account)),
      subtitle: Text(subtitleParts.join('  ·  ')),
      widget: TailscaleAccountView(accountId: account.id),
    );
  }

  Future<void> _applyChanges() async {
    if (_applying) {
      return;
    }
    setState(() {
      _applying = true;
    });
    String? error;
    try {
      await ref.read(setupActionProvider.notifier).applyTailscaleChanges();
    } on MessageException catch (exception) {
      error = exception.message;
    } catch (exception) {
      error = exception.toString();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _applying = false;
    });
    if (error != null) {
      context.showNotifier(error, level: MessageLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final accounts = ref.watch(tailscaleAccountsProvider);
    final snapshot = ref.watch(tailscaleAccountsSnapshotProvider);
    final hasUnapplied = ref.watch(hasUnappliedTailscaleChangesProvider);

    final sections = <Widget>[
      if (hasUnapplied)
        generateSection(
          items: [
            ListItem(
              leading: GlyphIcon(
                AppGlyphs.warning,
                color: context.colorScheme.warning,
              ),
              title: Text(appLocalizations.tailscaleUnappliedChanges),
              trailing: _applying
                  ? const CommonCircleLoading(size: 20)
                  : const GlyphIcon(AppGlyphs.check),
              onTap: _applying ? null : _applyChanges,
            ),
          ],
        ),
      generateSection(
        title: appLocalizations.tailscaleAccounts,
        items: accounts.accounts.isEmpty
            ? [
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.addCircle),
                  title: Text(appLocalizations.tailscaleAddAccount),
                  onTap: () => _handleAddOrUpdate(),
                ),
              ]
            : [
                for (final account in accounts.accounts)
                  _accountRow(appLocalizations, account, snapshot),
              ],
      ),
      generateSection(
        items: [
          ListItem.toggle(
            title: Text(appLocalizations.tailscaleAutoFollow),
            value: accounts.autoFollow,
            onChanged: (value) {
              ref
                  .read(tailscaleAccountsProvider.notifier)
                  .update((state) => state.copyWith(autoFollow: value));
            },
          ),
        ],
      ),
    ];

    return CommonScaffold(
      title: 'Tailscale',
      iconActions: [
        if (hasUnapplied)
          IconButtonData(
            glyph: AppGlyphs.check,
            tooltip: appLocalizations.tailscaleApplyChanges,
            isLoading: _applying,
            onPressed: _applying ? null : _applyChanges,
          ),
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: appLocalizations.tailscaleAddAccount,
          onPressed: () => _handleAddOrUpdate(),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: sections,
      ),
    );
  }
}

class TailscaleAccountView extends ConsumerStatefulWidget {
  const TailscaleAccountView({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<TailscaleAccountView> createState() =>
      _TailscaleAccountViewState();
}

class _TailscaleAccountViewState extends ConsumerState<TailscaleAccountView> {
  bool _applying = false;
  bool _testing = false;
  final Map<String, TailscalePingResult> _pingResults = {};

  Future<void> _handleTest() async {
    if (_testing) {
      return;
    }
    final peers = [
      for (final peer
          in _accountOf(
                ref.read(tailscaleAccountsProvider),
                widget.accountId,
              )?.peers ??
              const [])
        if (peer.enabled && peer.tailscaleIps.isNotEmpty) peer,
    ];
    if (peers.isEmpty) {
      return;
    }
    setState(() => _testing = true);
    try {
      for (final peer in peers) {
        final result = await ref
            .read(coreHandlerProvider)
            .pingTailscale(widget.accountId, peer.tailscaleIps.first);
        if (!mounted) {
          return;
        }
        setState(() => _pingResults[peer.key] = result);
      }
    } catch (error) {
      if (mounted) {
        context.showNotifier(error.toString(), level: MessageLevel.error);
      }
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  void _updateAccount(
    TailscaleAccountProps Function(TailscaleAccountProps account) update,
  ) {
    ref.read(tailscaleAccountsProvider.notifier).update((state) {
      return state.copyWith(
        accounts: [
          for (final item in state.accounts)
            item.id == widget.accountId ? update(item) : item,
        ],
      );
    });
  }

  Future<void> _handleAddOrUpdate(TailscaleAccountProps account) async {
    final accounts = ref.read(tailscaleAccountsProvider);
    final result = await showFormSheet<TailscaleAccountProps>(
      context: context,
      builder: (_) => _AccountForm(
        account: account,
        otherAccounts: [
          for (final item in accounts.accounts)
            if (item.id != account.id) item,
        ],
      ),
    );
    if (result != null) {
      _updateAccount((_) => result);
    }
  }

  Future<void> _applyChanges() async {
    if (_applying) {
      return;
    }
    setState(() {
      _applying = true;
    });
    String? error;
    try {
      await ref.read(setupActionProvider.notifier).applyTailscaleChanges();
    } on MessageException catch (exception) {
      error = exception.message;
    } catch (exception) {
      error = exception.toString();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _applying = false;
    });
    if (error != null) {
      context.showNotifier(error, level: MessageLevel.error);
    }
  }

  Future<void> _handleDelete(TailscaleAccountProps account) async {
    final appLocalizations = context.appLocalizations;
    final res = await dialogs.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(
        text: appLocalizations.deleteTip(_accountDisplayName(account)),
      ),
      destructive: true,
      confirmText: appLocalizations.delete,
    );
    if (res != true) {
      return;
    }
    ref.read(tailscaleAccountsProvider.notifier).update((state) {
      return state.copyWith(
        accounts: [
          for (final item in state.accounts)
            if (item.id != widget.accountId) item,
        ],
      );
    });
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _handleLogin() async {
    final error = await ref
        .read(coreHandlerProvider)
        .startTailscaleLogin(widget.accountId);
    if (!mounted) {
      return;
    }
    if (error.isNotEmpty) {
      context.showNotifier(error, level: MessageLevel.error);
    }
  }

  Future<void> _handleLogout() async {
    final error = await ref
        .read(coreHandlerProvider)
        .logoutTailscale(widget.accountId);
    if (!mounted) {
      return;
    }
    if (error.isNotEmpty) {
      context.showNotifier(error, level: MessageLevel.error);
    }
  }

  void _openAuthUrl(String authUrl) {
    final uri = Uri.tryParse(authUrl);
    if (uri == null) {
      return;
    }
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget? _statusSubtitle(
    AppLocalizations appLocalizations,
    TailscaleAccountState? state,
  ) {
    final lines = <Widget>[];
    final error = state?.error ?? '';
    if (error == _stubBuildError) {
      lines.add(Text(appLocalizations.tailscaleNotAvailable));
    } else if (error.isNotEmpty) {
      lines.add(Text(error));
    }
    if (state != null &&
        state.present &&
        state.backendState == 'Running' &&
        state.peerCount > 0) {
      lines.add(
        Text(
          appLocalizations.tailscaleOnlinePeerCount(
            state.onlinePeerCount,
            state.peerCount,
          ),
        ),
      );
    }
    if (lines.isEmpty) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines,
    );
  }

  List<Widget> _buildStatusItems(
    AppLocalizations appLocalizations,
    TailscaleAccountProps account,
    TailscaleAccountState? state,
  ) {
    final marks = _accountStatusMarks(context.colorScheme, account, state);
    final items = <Widget>[
      ListItem(
        leading: GlyphIcon(marks.glyph, color: marks.color),
        title: Text(
          _accountStateLabel(appLocalizations, account, state),
          style: AppTextStyle.headline.of(context).copyWith(color: marks.color),
        ),
        subtitle: _statusSubtitle(appLocalizations, state),
      ),
    ];

    if (state != null && state.isRunning) {
      items.add(
        ListItem(
          leading: const GlyphIcon(AppGlyphs.bolt),
          title: Text(appLocalizations.tailscaleTest),
          onTap: _testing ? null : _handleTest,
        ),
      );
    }

    if (state != null && state.backendState == 'NeedsLogin') {
      items.add(
        ListItem(
          leading: const GlyphIcon(AppGlyphs.key),
          title: Text(appLocalizations.tailscaleLogin),
          onTap: _handleLogin,
        ),
      );
    }

    if (state != null && state.present && state.backendState.isNotEmpty) {
      items.add(
        ListItem(
          leading: const GlyphIcon(AppGlyphs.lockOpen),
          title: Text(appLocalizations.tailscaleLogout),
          onTap: _handleLogout,
        ),
      );
    }

    if (state != null && state.authUrl.isNotEmpty) {
      items.add(
        ListItem(
          leading: const GlyphIcon(AppGlyphs.openExternal),
          title: Text(appLocalizations.tailscaleOpenAuthUrl),
          subtitle: Text(state.authUrl),
          onTap: () {
            _openAuthUrl(state.authUrl);
          },
        ),
      );
    }

    if (state != null && state.tailnet.isNotEmpty) {
      items.add(
        ListItem(
          leading: const GlyphIcon(AppGlyphs.connections),
          title: Text(appLocalizations.tailscaleTailnet),
          subtitle: Text(state.tailnet),
        ),
      );
    }

    if (state != null && state.tailscaleIps.isNotEmpty) {
      items.add(
        ListItem(
          leading: const GlyphIcon(AppGlyphs.locate),
          title: Text(appLocalizations.tailscaleTailscaleIps),
          subtitle: Text(state.tailscaleIps.join(', ')),
        ),
      );
    }

    if (state != null && state.magicDnsSuffix.isNotEmpty) {
      items.add(
        ListItem(
          leading: const GlyphIcon(AppGlyphs.dns),
          title: Text(appLocalizations.tailscaleMagicDnsSuffix),
          subtitle: Text(state.magicDnsSuffix),
        ),
      );
    }

    if (account.stateDir == 'tailscale') {
      items.add(
        ListItem(
          leading: GlyphIcon(
            AppGlyphs.info,
            color: context.colorScheme.warning,
          ),
          title: Text(appLocalizations.tailscaleStateDirLegacy),
        ),
      );
    }

    return items;
  }

  List<Widget> _buildExitNodeItems(
    AppLocalizations appLocalizations,
    TailscaleAccountProps account,
  ) {
    final exitPeers = [
      for (final peer in account.peers)
        if (peer.exitNodeOption) peer,
    ];
    String optionLabel(String value) {
      if (value.isEmpty) {
        return appLocalizations.tailscaleExitNodeNone;
      }
      if (value == 'auto:any') {
        return appLocalizations.tailscaleExitNodeAutoAny;
      }
      for (final peer in exitPeers) {
        if (peer.tailscaleIps.contains(value)) {
          return peer.dnsName.isNotEmpty ? peer.dnsName : value;
        }
      }
      return value;
    }

    return [
      ListItem<String>.options(
        title: Text(appLocalizations.tailscaleExitNode),
        options: [
          '',
          'auto:any',
          for (final peer in exitPeers) ...peer.tailscaleIps,
        ],
        value: account.exitNode,
        textBuilder: optionLabel,
        onChanged: (value) {
          _updateAccount((account) => account.copyWith(exitNode: value));
        },
      ),
      ListItem.toggle(
        title: Text(appLocalizations.tailscaleExitNodeAllowLanAccess),
        value: account.exitNodeAllowLanAccess,
        onChanged: (value) {
          _updateAccount(
            (account) => account.copyWith(exitNodeAllowLanAccess: value),
          );
        },
      ),
    ];
  }

  List<Widget> _buildRouteItems(
    AppLocalizations appLocalizations,
    TailscaleAccountProps account,
    Set<String> appliedVpnRoutes,
  ) {
    return [
      ListItem.toggle(
        title: Text(appLocalizations.tailscaleAcceptRoutes),
        value: account.acceptRoutes,
        onChanged: (value) {
          _updateAccount((account) => account.copyWith(acceptRoutes: value));
        },
      ),
      if (account.routes.isEmpty)
        ListItem(
          leading: const GlyphIcon(AppGlyphs.layers),
          title: Text(
            appLocalizations.nullTip(appLocalizations.tailscaleRoutes),
          ),
        )
      else
        for (final route in account.routes)
          ListItem.checkbox(
            title: Text(route.cidr),
            subtitle:
                route.enabled &&
                    system.isAndroid &&
                    isTailscaleSubnetNeedingVpnRoute(route.cidr) &&
                    !appliedVpnRoutes.contains(route.cidr)
                ? Text(appLocalizations.tailscalePendingVpnRestart)
                : null,
            value: route.enabled,
            onChanged: (value) {
              _updateAccount((account) {
                return account.copyWith(
                  routes: [
                    for (final item in account.routes)
                      item.cidr == route.cidr
                          ? item.copyWith(enabled: value ?? false)
                          : item,
                  ],
                );
              });
            },
          ),
    ];
  }

  List<Widget> _buildPeerItems(
    AppLocalizations appLocalizations,
    TailscaleAccountProps account,
    TailscaleAccountState? state,
  ) {
    if (account.peers.isEmpty) {
      return [
        ListItem(
          leading: const GlyphIcon(AppGlyphs.devices),
          title: Text(
            appLocalizations.nullTip(appLocalizations.tailscalePeers),
          ),
        ),
      ];
    }

    final livePeers = {
      for (final peer in state?.peers ?? const <TailscalePeerInfo>[])
        if (peer.mergeKey.isNotEmpty) peer.mergeKey: peer,
    };

    return [
      for (final peer in account.peers)
        _peerItem(appLocalizations, peer, livePeers[peer.key]),
    ];
  }

  Widget _peerItem(
    AppLocalizations appLocalizations,
    TailscalePeerEntry peer,
    TailscalePeerInfo? live,
  ) {
    final badge = _peerBadge(live);
    return ListItem.checkbox(
      leading: GlyphIcon(
        badge.glyph,
        color: live?.online == true
            ? badge.color
            : context.colorScheme.onSurfaceVariant,
      ),
      title: Text(_peerEntryTitle(peer)),
      subtitle: _peerSubtitle(appLocalizations, peer, live),
      value: peer.enabled,
      onChanged: (value) {
        _updateAccount((account) {
          return account.copyWith(
            peers: [
              for (final item in account.peers)
                item.key == peer.key
                    ? item.copyWith(enabled: value ?? false)
                    : item,
            ],
          );
        });
      },
    );
  }

  ({Color color, Glyph glyph}) _peerBadge(TailscalePeerInfo? peer) {
    final colorScheme = context.colorScheme;
    if (peer == null) {
      return (color: colorScheme.onSurfaceVariant, glyph: AppGlyphs.devices);
    }
    return switch (peer.connectionType) {
      TailscalePeerConnectionType.direct => (
        color: colorScheme.success,
        glyph: AppGlyphs.bolt,
      ),
      TailscalePeerConnectionType.derp => (
        color: colorScheme.primary,
        glyph: AppGlyphs.link,
      ),
      TailscalePeerConnectionType.idle => (
        color: colorScheme.warning,
        glyph: AppGlyphs.clock,
      ),
      _ => (color: colorScheme.onSurfaceVariant, glyph: AppGlyphs.block),
    };
  }

  Widget? _peerSubtitle(
    AppLocalizations appLocalizations,
    TailscalePeerEntry peer,
    TailscalePeerInfo? live,
  ) {
    final ping = _pingResults[peer.key];
    final lines = <Widget>[
      if (peer.tailscaleIps.isNotEmpty)
        Text(
          peer.tailscaleIps.join(', '),
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      if (ping != null)
        Text(
          ping.error.isNotEmpty
              ? ping.error
              : '${ping.latencyMs} ms · ${ping.via}',
        ),
      if (live != null && live.primaryRoutes.isNotEmpty)
        Text(
          '${appLocalizations.tailscaleRoutes}: ${live.primaryRoutes.join(', ')}',
        ),
      if (peer.exitNodeOption) Text(appLocalizations.tailscaleExitNode),
    ];
    if (live != null) {
      final connectionDetail = switch (live.connectionType) {
        TailscalePeerConnectionType.direct => live.curAddr,
        TailscalePeerConnectionType.derp => live.relay,
        _ => '',
      };
      final metaParts = <String>[
        ?_relativeTime(context, live.lastHandshake),
        if (connectionDetail.isNotEmpty) connectionDetail,
        if (live.rxBytes > 0 || live.txBytes > 0)
          '↓ ${_formatBytes(live.rxBytes)} · ↑ ${_formatBytes(live.txBytes)}',
      ];
      if (metaParts.isNotEmpty) {
        lines.add(Text(metaParts.join('  ·  ')));
      }
    }
    if (lines.isEmpty) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final accounts = ref.watch(tailscaleAccountsProvider);
    final snapshot = ref.watch(tailscaleAccountsSnapshotProvider);
    final appliedVpnRoutes = ref.watch(tailscaleRuntimeRoutesProvider).toSet();
    final account = _accountOf(accounts, widget.accountId);
    if (account == null) {
      return const CommonScaffold(title: 'Tailscale', body: SizedBox.shrink());
    }
    final state = _stateOf(snapshot, widget.accountId);
    final hasUnapplied = ref.watch(hasUnappliedTailscaleChangesProvider);

    final sections = <Widget>[
      generateSection(
        title: appLocalizations.status,
        items: _buildStatusItems(appLocalizations, account, state),
      ),
      generateSection(
        title: appLocalizations.account,
        items: [
          ListItem.toggle(
            title: Text(appLocalizations.enabled),
            value: account.enable,
            onChanged: (value) {
              _updateAccount((account) => account.copyWith(enable: value));
            },
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.edit),
            title: Text(appLocalizations.tailscaleEditAccount),
            onTap: () => _handleAddOrUpdate(account),
          ),
          ListItem(
            leading: GlyphIcon(
              AppGlyphs.delete,
              color: context.colorScheme.error,
            ),
            title: Text(appLocalizations.tailscaleDeleteAccount),
            onTap: () => _handleDelete(account),
          ),
        ],
      ),
      generateSection(
        title: appLocalizations.tailscaleExitNode,
        items: _buildExitNodeItems(appLocalizations, account),
      ),
      generateSection(
        title: appLocalizations.tailscaleRoutes,
        items: _buildRouteItems(appLocalizations, account, appliedVpnRoutes),
      ),
      generateSection(
        title: appLocalizations.tailscalePeers,
        items: _buildPeerItems(appLocalizations, account, state),
      ),
      generateSection(
        items: [
          ListItem.open(
            leading: const GlyphIcon(AppGlyphs.rules),
            title: Text(appLocalizations.tailscaleExtraRules),
            subtitle: Text(
              account.extraRules.isEmpty
                  ? appLocalizations.none
                  : appLocalizations.itemsCount(account.extraRules.length),
            ),
            widget: ListEditView(
              title: appLocalizations.tailscaleExtraRules,
              items: account.extraRules,
              titleBuilder: (item) => Text(item),
            ),
            onChanged: (items) {
              if (items is! List) {
                return;
              }
              _updateAccount(
                (account) =>
                    account.copyWith(extraRules: List<String>.from(items)),
              );
            },
          ),
        ],
      ),
    ];

    return CommonScaffold(
      title: _accountDisplayName(account),
      iconActions: [
        if (hasUnapplied)
          IconButtonData(
            glyph: AppGlyphs.check,
            tooltip: appLocalizations.tailscaleApplyChanges,
            isLoading: _applying,
            onPressed: _applying ? null : _applyChanges,
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: sections,
      ),
    );
  }
}

class _AccountForm extends StatefulWidget {
  final TailscaleAccountProps? account;
  final List<TailscaleAccountProps> otherAccounts;

  const _AccountForm({required this.account, required this.otherAccounts});

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  late final TextEditingController _labelController;
  late final TextEditingController _controlUrlController;
  late final TextEditingController _hostnameController;
  late final TextEditingController _authKeyController;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _labelController = TextEditingController(text: account?.label);
    _controlUrlController = TextEditingController(text: account?.controlUrl);
    _hostnameController = TextEditingController(text: account?.hostname);
    _authKeyController = TextEditingController(text: account?.authKey);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _controlUrlController.dispose();
    _hostnameController.dispose();
    _authKeyController.dispose();
    super.dispose();
  }

  String? _labelIssue() {
    final appLocalizations = context.appLocalizations;
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      return appLocalizations.emptyTip(appLocalizations.tailscaleAccountLabel);
    }
    final derived = 'TAILNET-${sanitizeTailscaleLabel(label)}';
    final taken = widget.otherAccounts.any(
      (account) => account.outboundName == derived,
    );
    if (taken) {
      return appLocalizations.tailscaleLabelConflict(derived);
    }
    return null;
  }

  String? _controlUrlIssue() {
    final value = _controlUrlController.text.trim();
    if (value.isEmpty) {
      return null;
    }
    if (!value.isUrl) {
      return context.appLocalizations.urlTip(
        context.appLocalizations.tailscaleControlUrl,
      );
    }
    return null;
  }

  void _handleSave() {
    setState(() {
      _attempted = true;
    });
    if (_labelIssue() != null || _controlUrlIssue() != null) {
      return;
    }
    final base = widget.account ?? TailscaleAccountProps(id: uuidV4);
    Navigator.of(context).pop(
      base.copyWith(
        label: _labelController.text.trim(),
        controlUrl: _controlUrlController.text.trim(),
        hostname: _hostnameController.text.trim(),
        authKey: _authKeyController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final labelIssue = _attempted ? _labelIssue() : null;
    final controlUrlIssue = _attempted ? _controlUrlIssue() : null;
    return FormPage(
      title: widget.account == null
          ? appLocalizations.tailscaleAddAccount
          : appLocalizations.tailscaleEditAccount,
      onSave: _handleSave,
      error: labelIssue ?? controlUrlIssue,
      children: [
        generateSection(
          items: [
            FormRow(
              title: appLocalizations.tailscaleAccountLabel,
              invalid: labelIssue != null,
              trailing: FormRowTextField(
                controller: _labelController,
                autofocus: widget.account == null,
                hintText: 'work',
                autocorrect: false,
                textInputAction: TextInputAction.next,
                inputFormatters: TextInputLimits.limit(TextInputLimits.name),
                onChanged: (_) {
                  if (_attempted) {
                    setState(() {});
                  }
                },
              ),
            ),
            FormRow(
              title: appLocalizations.tailscaleControlUrl,
              invalid: controlUrlIssue != null,
              trailing: FormRowTextField(
                controller: _controlUrlController,
                hintText: 'https://',
                autocorrect: false,
                textInputAction: TextInputAction.next,
                inputFormatters: TextInputLimits.limit(TextInputLimits.url),
                onChanged: (_) {
                  if (_attempted) {
                    setState(() {});
                  }
                },
              ),
            ),
            FormRow(
              title: appLocalizations.tailscaleHostname,
              trailing: FormRowTextField(
                controller: _hostnameController,
                hintText: appLocalizations.defaultText,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                inputFormatters: TextInputLimits.limit(TextInputLimits.name),
              ),
            ),
            FormRow(
              title: appLocalizations.tailscaleAuthKey,
              trailing: FormRowSecretTextField(
                controller: _authKeyController,
                hintText: appLocalizations.defaultText,
                textInputAction: TextInputAction.done,
                inputFormatters: TextInputLimits.limit(
                  TextInputLimits.password,
                ),
                onFieldSubmitted: (_) => _handleSave(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
