import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/svg.dart';

class CommonTargetIcon extends StatelessWidget {
  final String src;
  final double size;

  const CommonTargetIcon({super.key, required this.src, required this.size});

  Widget _defaultIcon() {
    return Icon(IconsExt.target, size: size);
  }

  Widget _buildIcon() {
    if (src.isEmpty) {
      return _defaultIcon();
    }

    final base64 = src.getBase64;
    if (base64 != null) {
      return Image.memory(
        base64,
        gaplessPlayback: true,
        errorBuilder: (_, error, _) {
          return _defaultIcon();
        },
      );
    }

    return ImageCacheWidget(src: src, defaultWidget: _defaultIcon());
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: _buildIcon());
  }
}

final _cacheMange = DefaultCacheManager();

class ImageCacheWidget extends StatefulWidget {
  final String src;
  final Widget defaultWidget;

  const ImageCacheWidget({
    super.key,
    required this.src,
    required this.defaultWidget,
  });

  @override
  State<ImageCacheWidget> createState() => _ImageCacheWidgetState();
}

class _ImageCacheWidgetState extends State<ImageCacheWidget> {
  final ValueNotifier<File?> _imageNotifier = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _getImageFormCache();
  }

  void _getImageFormCache() async {
    final src = widget.src;
    final cacheFile = await _cacheMange.getFileFromCache(src);
    if (!mounted) {
      return;
    }
    if (cacheFile != null) {
      _imageNotifier.value = cacheFile.file;
      if (cacheFile.validTill.isAfter(DateTime.now())) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    _imageNotifier.value = (await _cacheMange.downloadFile(src, key: src)).file;
  }

  @override
  void dispose() {
    _imageNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<File?>(
      valueListenable: _imageNotifier,
      builder: (_, data, _) {
        if (data == null) {
          return widget.defaultWidget;
        }
        return widget.src.isSvg
            ? SvgPicture.file(
                data,
                errorBuilder: (_, _, _) => widget.defaultWidget,
              )
            : Image.file(data, errorBuilder: (_, _, _) => widget.defaultWidget);
      },
    );
  }
}

class TailscaleIcon extends Icon {
  const TailscaleIcon({super.key, super.size, super.color, super.semanticLabel})
    : super(null);

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final resolvedColor =
        color ??
        iconTheme.color ??
        Theme.of(context).iconTheme.color ??
        Colors.black;

    return Semantics(
      label: semanticLabel,
      child: SizedBox.square(
        dimension: resolvedSize,
        child: CustomPaint(
          painter: _TailscaleIconPainter(color: resolvedColor),
        ),
      ),
    );
  }
}

class _TailscaleIconPainter extends CustomPainter {
  final Color color;

  const _TailscaleIconPainter({required this.color});

  static const _viewBoxSize = Size(23, 23);
  static const _circles = <({Offset center, double radius, double opacity})>[
    (center: Offset(3.4, 3.25), radius: 2.7, opacity: 0.2),
    (center: Offset(3.4, 11.3), radius: 2.7, opacity: 1),
    (center: Offset(3.4, 19.5), radius: 2.7, opacity: 0.2),
    (center: Offset(11.5, 11.3), radius: 2.7, opacity: 1),
    (center: Offset(11.5, 19.5), radius: 2.7, opacity: 1),
    (center: Offset(11.5, 3.25), radius: 2.7, opacity: 0.2),
    (center: Offset(19.5, 3.25), radius: 2.7, opacity: 0.2),
    (center: Offset(19.5, 11.3), radius: 2.7, opacity: 1),
    (center: Offset(19.5, 19.5), radius: 2.7, opacity: 0.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = Size(
      size.width / _viewBoxSize.width,
      size.height / _viewBoxSize.height,
    );

    for (final circle in _circles) {
      final paint = Paint()..color = color.withValues(alpha: circle.opacity);
      canvas.drawCircle(
        Offset(circle.center.dx * scale.width, circle.center.dy * scale.height),
        circle.radius * scale.shortestSide,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TailscaleIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
