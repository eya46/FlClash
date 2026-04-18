import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class VPNItem extends ConsumerWidget {
  const VPNItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final enable = ref.watch(
      vpnSettingProvider.select((state) => state.enable),
    );
    return ListItem.switchItem(
      title: const Text('VPN'),
      subtitle: Text(appLocalizations.vpnEnableDesc),
      delegate: SwitchDelegate(
        value: enable,
        onChanged: (value) async {
          ref
              .read(vpnSettingProvider.notifier)
              .update((state) => state.copyWith(enable: value));
        },
      ),
    );
  }
}

class TUNItem extends ConsumerWidget {
  const TUNItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final enable = ref.watch(
      patchClashConfigProvider.select((state) => state.tun.enable),
    );

    return ListItem.switchItem(
      title: Text(appLocalizations.tun),
      subtitle: Text(appLocalizations.tunDesc),
      delegate: SwitchDelegate(
        value: enable,
        onChanged: (value) async {
          ref
              .read(patchClashConfigProvider.notifier)
              .update((state) => state.copyWith.tun(enable: value));
        },
      ),
    );
  }
}

class AllowBypassItem extends ConsumerWidget {
  const AllowBypassItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final allowBypass = ref.watch(
      vpnSettingProvider.select((state) => state.allowBypass),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.allowBypass),
      subtitle: Text(appLocalizations.allowBypassDesc),
      delegate: SwitchDelegate(
        value: allowBypass,
        onChanged: (bool value) async {
          ref
              .read(vpnSettingProvider.notifier)
              .update((state) => state.copyWith(allowBypass: value));
        },
      ),
    );
  }
}

class VpnSystemProxyItem extends ConsumerWidget {
  const VpnSystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final systemProxy = ref.watch(
      vpnSettingProvider.select((state) => state.systemProxy),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.systemProxy),
      subtitle: Text(appLocalizations.systemProxyDesc),
      delegate: SwitchDelegate(
        value: systemProxy,
        onChanged: (bool value) async {
          ref
              .read(vpnSettingProvider.notifier)
              .update((state) => state.copyWith(systemProxy: value));
        },
      ),
    );
  }
}

class SystemProxyItem extends ConsumerWidget {
  const SystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final systemProxy = ref.watch(
      networkSettingProvider.select((state) => state.systemProxy),
    );

    return ListItem.switchItem(
      title: Text(appLocalizations.systemProxy),
      subtitle: Text(appLocalizations.systemProxyDesc),
      delegate: SwitchDelegate(
        value: systemProxy,
        onChanged: (bool value) async {
          ref
              .read(networkSettingProvider.notifier)
              .update((state) => state.copyWith(systemProxy: value));
        },
      ),
    );
  }
}

class Ipv6Item extends ConsumerWidget {
  const Ipv6Item({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final ipv6 = ref.watch(vpnSettingProvider.select((state) => state.ipv6));
    return ListItem.switchItem(
      title: const Text('IPv6'),
      subtitle: Text(appLocalizations.ipv6InboundDesc),
      delegate: SwitchDelegate(
        value: ipv6,
        onChanged: (bool value) async {
          ref
              .read(vpnSettingProvider.notifier)
              .update((state) => state.copyWith(ipv6: value));
        },
      ),
    );
  }
}

class AutoSetSystemDnsItem extends ConsumerWidget {
  const AutoSetSystemDnsItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final autoSetSystemDns = ref.watch(
      networkSettingProvider.select((state) => state.autoSetSystemDns),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.autoSetSystemDns),
      delegate: SwitchDelegate(
        value: autoSetSystemDns,
        onChanged: (bool value) async {
          ref
              .read(networkSettingProvider.notifier)
              .update((state) => state.copyWith(autoSetSystemDns: value));
        },
      ),
    );
  }
}

class TunStackItem extends ConsumerWidget {
  const TunStackItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final stack = ref.watch(
      patchClashConfigProvider.select((state) => state.tun.stack),
    );

    return ListItem.options(
      title: Text(appLocalizations.stackMode),
      subtitle: Text(stack.name),
      delegate: OptionsDelegate<TunStack>(
        value: stack,
        options: TunStack.values,
        textBuilder: (value) => value.name,
        onChanged: (value) {
          if (value == null) {
            return;
          }
          ref
              .read(patchClashConfigProvider.notifier)
              .update((state) => state.copyWith.tun(stack: value));
        },
        title: appLocalizations.stackMode,
      ),
    );
  }
}

class BypassDomainItem extends ConsumerWidget {
  const BypassDomainItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final bypassDomain = ref.watch(
      networkSettingProvider.select((state) => state.bypassDomain),
    );
    return ListItem.open(
      title: Text(appLocalizations.bypassDomain),
      subtitle: Text(appLocalizations.bypassDomainDesc),
      delegate: OpenDelegate(
        blur: false,
        widget: ListInputPage(
          title: appLocalizations.bypassDomain,
          items: bypassDomain,
          titleBuilder: (item) => Text(item),
        ),
        onChanged: (items) {
          ref
              .read(networkSettingProvider.notifier)
              .update(
                (state) => state.copyWith(bypassDomain: List.from(items)),
              );
        },
      ),
    );
  }
}

class DNSHijackingItem extends ConsumerWidget {
  const DNSHijackingItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final dnsHijacking = ref.watch(
      vpnSettingProvider.select((state) => state.dnsHijacking),
    );
    return ListItem<RouteMode>.switchItem(
      title: Text(appLocalizations.dnsHijacking),
      delegate: SwitchDelegate(
        value: dnsHijacking,
        onChanged: (value) async {
          ref
              .read(vpnSettingProvider.notifier)
              .update((state) => state.copyWith(dnsHijacking: value));
        },
      ),
    );
  }
}

class TailscaleEnableItem extends ConsumerWidget {
  const TailscaleEnableItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final enable = ref.watch(
      tailscaleSettingProvider.select((state) => state.enable),
    );
    return ListItem.switchItem(
      title: const Text('Enable Tailscale'),
      subtitle: const Text('Use tsnet for Tailscale subnet routes.'),
      delegate: SwitchDelegate(
        value: enable,
        onChanged: (bool value) async {
          ref
              .read(tailscaleSettingProvider.notifier)
              .update((state) => state.copyWith(enable: value));
        },
      ),
    );
  }
}

class TailscaleAcceptRoutesItem extends ConsumerWidget {
  const TailscaleAcceptRoutesItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final acceptRoutes = ref.watch(
      tailscaleSettingProvider.select((state) => state.acceptRoutes),
    );
    return ListItem.switchItem(
      title: const Text('Accept Tailscale Routes'),
      subtitle: const Text(
        'Advertised subnet routes are handled by Tailscale instead of Mihomo.',
      ),
      delegate: SwitchDelegate(
        value: acceptRoutes,
        onChanged: (bool value) async {
          ref
              .read(tailscaleSettingProvider.notifier)
              .update((state) => state.copyWith(acceptRoutes: value));
        },
      ),
    );
  }
}

class TailscaleHostnameItem extends ConsumerWidget {
  const TailscaleHostnameItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final hostname = ref.watch(
      tailscaleSettingProvider.select((state) => state.hostname),
    );
    return ListItem.input(
      title: const Text('Tailscale Hostname'),
      subtitle: Text(
        hostname.isEmpty ? appLocalizations.defaultText : hostname,
      ),
      delegate: InputDelegate(
        title: 'Tailscale Hostname',
        value: hostname,
        resetValue: '',
        onChanged: (String? value) {
          if (value == null) {
            return;
          }
          ref
              .read(tailscaleSettingProvider.notifier)
              .update((state) => state.copyWith(hostname: value));
        },
      ),
    );
  }
}

class TailscaleAuthKeyItem extends ConsumerWidget {
  const TailscaleAuthKeyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final authKey = ref.watch(
      tailscaleSettingProvider.select((state) => state.authKey),
    );
    return ListItem.input(
      title: const Text('Tailscale Auth Key'),
      subtitle: Text(
        authKey.isEmpty ? appLocalizations.defaultText : 'Configured',
      ),
      delegate: InputDelegate(
        title: 'Tailscale Auth Key',
        value: authKey,
        resetValue: '',
        onChanged: (String? value) {
          if (value == null) {
            return;
          }
          ref
              .read(tailscaleSettingProvider.notifier)
              .update((state) => state.copyWith(authKey: value));
        },
      ),
    );
  }
}

class TailscaleControlUrlItem extends ConsumerWidget {
  const TailscaleControlUrlItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final controlUrl = ref.watch(
      tailscaleSettingProvider.select((state) => state.controlUrl),
    );
    return ListItem.input(
      title: const Text('Tailscale Control URL'),
      subtitle: Text(
        controlUrl.isEmpty ? appLocalizations.defaultText : controlUrl,
      ),
      delegate: InputDelegate(
        title: 'Tailscale Control URL',
        value: controlUrl,
        resetValue: '',
        validator: (String? value) {
          if (value == null || value.isEmpty) {
            return null;
          }
          if (!value.isUrl) {
            return appLocalizations.urlTip('Control URL');
          }
          return null;
        },
        onChanged: (String? value) {
          if (value == null) {
            return;
          }
          ref
              .read(tailscaleSettingProvider.notifier)
              .update((state) => state.copyWith(controlUrl: value));
        },
      ),
    );
  }
}

class RouteModeItem extends ConsumerWidget {
  const RouteModeItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final routeMode = ref.watch(
      networkSettingProvider.select((state) => state.routeMode),
    );
    return ListItem<RouteMode>.options(
      title: Text(appLocalizations.routeMode),
      subtitle: Text(Intl.message('routeMode_${routeMode.name}')),
      delegate: OptionsDelegate<RouteMode>(
        title: appLocalizations.routeMode,
        options: RouteMode.values,
        onChanged: (RouteMode? value) {
          if (value == null) {
            return;
          }
          ref
              .read(networkSettingProvider.notifier)
              .update((state) => state.copyWith(routeMode: value));
        },
        textBuilder: (routeMode) => Intl.message('routeMode_${routeMode.name}'),
        value: routeMode,
      ),
    );
  }
}

class RouteAddressItem extends ConsumerWidget {
  const RouteAddressItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final bypassPrivate = ref.watch(
      networkSettingProvider.select(
        (state) => state.routeMode == RouteMode.bypassPrivate,
      ),
    );
    if (bypassPrivate) {
      return Container();
    }
    final routeAddress = ref.watch(
      patchClashConfigProvider.select((state) => state.tun.routeAddress),
    );
    return ListItem.open(
      title: Text(appLocalizations.routeAddress),
      subtitle: Text(appLocalizations.routeAddressDesc),
      delegate: OpenDelegate(
        blur: false,
        maxWidth: 360,
        widget: ListInputPage(
          title: appLocalizations.routeAddress,
          items: routeAddress,
          titleBuilder: (item) => Text(item),
        ),
        onChanged: (items) {
          ref
              .read(patchClashConfigProvider.notifier)
              .update(
                (state) => state.copyWith.tun(routeAddress: List.from(items)),
              );
        },
      ),
    );
  }
}

final networkItems = [
  if (system.isAndroid) const VPNItem(),
  if (system.isAndroid)
    ...generateSection(
      title: 'VPN',
      items: [
        const VpnSystemProxyItem(),
        const BypassDomainItem(),
        const AllowBypassItem(),
        const Ipv6Item(),
        const DNSHijackingItem(),
      ],
    ),
  if (system.isDesktop)
    ...generateSection(
      title: appLocalizations.system,
      items: [SystemProxyItem(), BypassDomainItem()],
    ),
  ...generateSection(
    title: appLocalizations.options,
    items: [
      if (system.isDesktop) const TUNItem(),
      if (system.isMacOS) const AutoSetSystemDnsItem(),
      const TunStackItem(),
      if (!system.isDesktop) ...[
        const RouteModeItem(),
        const RouteAddressItem(),
      ],
    ],
  ),
];

class NetworkListView extends StatelessWidget {
  const NetworkListView({super.key});

  @override
  Widget build(BuildContext context) {
    return generateListView(networkItems);
  }
}
