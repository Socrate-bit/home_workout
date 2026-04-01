import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'quick_pose_service.dart';

/// Embeds the native QuickPose camera + skeleton overlay (UIKit / AndroidView).
class QuickPoseCameraView extends StatelessWidget {
  const QuickPoseCameraView({
    super.key,
    this.creationParams = const <String, dynamic>{},
    this.hitTestBehavior = PlatformViewHitTestBehavior.opaque,
  });

  final Map<String, dynamic> creationParams;
  final PlatformViewHitTestBehavior hitTestBehavior;

  @override
  Widget build(BuildContext context) {
    const viewType = kQuickPosePlatformViewType;
    final params = <String, dynamic>{
      ...creationParams,
    };

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: hitTestBehavior,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: hitTestBehavior,
      );
    }

    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text('QuickPose camera is supported on iOS and Android.'),
      ),
    );
  }
}
