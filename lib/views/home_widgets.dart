import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/plugins/widget.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';

Future<void> showHomeWidgetsSheet(
  BuildContext context, {
  WidgetChannel? channel,
}) {
  return showNestedSheet<void>(
    context,
    builder: (_) => HomeWidgetsSheet(channel: channel),
  );
}

class HomeWidgetsSheet extends StatefulWidget {
  const HomeWidgetsSheet({super.key, this.channel});

  final WidgetChannel? channel;

  @override
  State<HomeWidgetsSheet> createState() => _HomeWidgetsSheetState();
}

class _HomeWidgetsSheetState extends State<HomeWidgetsSheet> {
  WidgetPinKind? _pinningKind;
  bool? _pinSupported;

  WidgetChannel? get _channel => widget.channel ?? widgetChannel;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPinSupport());
  }

  Future<void> _loadPinSupport() async {
    final target = _channel;
    if (target == null) {
      return;
    }
    final supported = await target.isRequestPinSupported();
    if (!mounted) {
      return;
    }
    setState(() => _pinSupported = supported);
  }

  Future<void> _requestPin(WidgetPinKind kind) async {
    if (_pinningKind != null) {
      return;
    }
    setState(() => _pinningKind = kind);
    final appLocalizations = context.appLocalizations;
    var pinned = false;
    try {
      final target = _channel;
      if (target != null) {
        pinned = await target.requestPinWidget(kind);
      }
    } catch (error) {
      commonPrint.log(
        'requestPinWidget error: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _pinningKind = null);
      }
    }
    if (!mounted) {
      return;
    }
    if (pinned) {
      dialogs.showBanner(
        appLocalizations.homeWidgetPinRequested,
        level: BannerLevel.success,
      );
    } else {
      dialogs.showBanner(
        appLocalizations.homeWidgetPinUnsupported,
        level: BannerLevel.warning,
      );
    }
  }

  String _badgeLabel(WidgetPinKind kind) {
    return switch (kind) {
      WidgetPinKind.compact2x2 => '2×2',
      WidgetPinKind.wide4x2 => '4×2',
      WidgetPinKind.bar4x1 => '4×1',
    };
  }

  String _titleFor(AppLocalizations l, WidgetPinKind kind) {
    return switch (kind) {
      WidgetPinKind.compact2x2 => l.homeWidget2x2Title,
      WidgetPinKind.wide4x2 => l.homeWidget4x2Title,
      WidgetPinKind.bar4x1 => l.homeWidget4x1Title,
    };
  }

  String _descFor(AppLocalizations l, WidgetPinKind kind) {
    return switch (kind) {
      WidgetPinKind.compact2x2 => l.homeWidget2x2Desc,
      WidgetPinKind.wide4x2 => l.homeWidget4x2Desc,
      WidgetPinKind.bar4x1 => l.homeWidget4x1Desc,
    };
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final footer = _pinSupported == false
        ? appLocalizations.homeWidgetPinUnsupported
        : appLocalizations.homeWidgetsDesc;
    return Scaffold(
      title: appLocalizations.homeWidgets,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 20 + context.bottomInset,
        ),
        children: [
          generateSection(
            items: [
              for (final kind in WidgetPinKind.values)
                ListItem(
                  leading: _WidgetSizeBadge(label: _badgeLabel(kind)),
                  title: Text(_titleFor(appLocalizations, kind)),
                  subtitle: Text(_descFor(appLocalizations, kind)),
                  trailing: const GlyphIcon(AppGlyphs.addCircle),
                  onTap: _pinningKind == null ? () => _requestPin(kind) : null,
                ),
            ],
            footer: footer,
          ),
        ],
      ),
    );
  }
}

class _WidgetSizeBadge extends StatelessWidget {
  const _WidgetSizeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.md,
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
