import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Fades outgoing content early so transparent pages do not linger underneath.
class ObsidianPageTransitionsBuilder extends FadeForwardsPageTransitionsBuilder {
  const ObsidianPageTransitionsBuilder() : super(backgroundColor: Colors.transparent);

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);
}

/// Keeps Apple's slide and back gesture while clearing transparent pages early.
class ObsidianCupertinoPageTransitionsBuilder extends CupertinoPageTransitionsBuilder {
  const ObsidianCupertinoPageTransitionsBuilder();

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _CupertinoPageFade(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    linearTransition: route.popGestureInProgress,
    child: super.buildTransitions(route, context, animation, secondaryAnimation, child),
  );

  static Widget? _delegatedTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (child == null) {
      return null;
    }

    return _CupertinoPageFade(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      linearTransition: Navigator.of(context).userGestureInProgress,
      child: CupertinoPageTransition.delegatedTransition(
        context,
        animation,
        secondaryAnimation,
        allowSnapshotting,
        child,
      )!,
    );
  }
}

class _CupertinoPageFade extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool linearTransition;
  final Widget child;

  const _CupertinoPageFade({
    required this.animation,
    required this.secondaryAnimation,
    required this.linearTransition,
    required this.child,
  });

  @override
  State<_CupertinoPageFade> createState() => _CupertinoPageFadeState();
}

class _CupertinoPageFadeState extends State<_CupertinoPageFade> {
  late CurvedAnimation _primary;
  late CurvedAnimation _secondary;

  @override
  void initState() {
    super.initState();

    _configureAnimations();
  }

  @override
  void didUpdateWidget(covariant _CupertinoPageFade oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.animation != widget.animation || oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      _primary.dispose();
      _secondary.dispose();

      _configureAnimations();
    }
  }

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();

    super.dispose();
  }

  void _configureAnimations() {
    // Fade within the first fifth of a push or pop, rather than waiting for
    // the slide to finish. Reverse curves reveal the returning page early.
    _primary = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0, 0.2, curve: Curves.easeOut),
      reverseCurve: const Interval(0.8, 1, curve: Curves.easeIn),
    );
    _secondary = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: const Interval(0, 0.2, curve: Curves.easeOut),
      reverseCurve: const Interval(0.8, 1, curve: Curves.easeIn),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_primary, _secondary]),
    child: widget.child,
    builder: (context, child) {
      // Keep opacity tied to the finger during interactive back navigation.
      final primary = widget.linearTransition ? widget.animation.value : _primary.value;
      final secondary = widget.linearTransition ? widget.secondaryAnimation.value : _secondary.value;

      return Opacity(opacity: primary * (1 - secondary), child: child);
    },
  );
}
