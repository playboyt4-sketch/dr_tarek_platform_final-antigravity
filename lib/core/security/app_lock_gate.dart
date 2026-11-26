import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/domain/entities/session_state.dart';
import '../../features/authentication/presentation/providers/session_provider.dart';
import '../../features/authentication/presentation/widgets/brand_signature_logo.dart';
import '../theme/app_semantic_colors.dart';
import 'biometric_lock_service.dart';

/// App-wide biometric lock gate wrapping the router tree.
///
/// Active ONLY when the user is authenticated (`SessionAuthenticated`) and has
/// enabled biometric lock (`biometricLockEnabledProvider == true`):
/// - Locks immediately on cold start and invokes biometric authentication.
/// - Locks when returning from background (`AppLifecycleState.resumed`) after
///   more than [backgroundLockThreshold] (default 30 seconds).
/// - Never activates during logout and resets lock state when signed out.
class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;
  final DateTime Function() now;
  final Duration backgroundLockThreshold;

  const AppLockGate({
    required this.child,
    this.now = DateTime.now,
    this.backgroundLockThreshold = const Duration(seconds: 30),
    super.key,
  });

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _isAuthenticating = false;
  bool _coldStartHandled = false;
  bool _sawUnauthenticated = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final session = ref.read(sessionProvider).asData?.value;
    final enabled = ref.read(biometricLockEnabledProvider);
    final lockState = ref.read(appLockStateProvider);

    if (session is SessionUnauthenticated || lockState.isLoggingOut) {
      _sawUnauthenticated = true;
      _coldStartHandled = true;
    } else if (session is SessionAuthenticated && !lockState.isLoggingOut) {
      _coldStartHandled = true;
      if (enabled) {
        _isLocked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_authenticate());
          }
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _isCurrentlyEligible() {
    final enabled = ref.read(biometricLockEnabledProvider);
    final lockState = ref.read(appLockStateProvider);
    final session = ref.read(sessionProvider).asData?.value;
    return enabled && !lockState.isLoggingOut && session is SessionAuthenticated;
  }

  void _resetLockState({bool markUnauthenticated = false}) {
    _backgroundedAt = null;
    _isAuthenticating = false;
    if (markUnauthenticated) {
      _sawUnauthenticated = true;
      _coldStartHandled = true;
    }
    if (_isLocked && mounted) {
      setState(() => _isLocked = false);
    } else {
      _isLocked = false;
    }
  }

  Future<void> _authenticate() async {
    if (!mounted || _isAuthenticating || !_isLocked || !_isCurrentlyEligible()) {
      return;
    }
    setState(() => _isAuthenticating = true);

    final success = await ref.read(biometricLockServiceProvider).authenticate(
          localizedReason: 'يرجى تأكيد هويتك لفتح التطبيق',
        );

    if (!mounted) return;
    if (!_isCurrentlyEligible()) {
      _resetLockState();
      return;
    }

    setState(() {
      _isAuthenticating = false;
      if (success) {
        _isLocked = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isCurrentlyEligible()) {
      _backgroundedAt = null;
      return;
    }

    if (state == AppLifecycleState.paused) {
      if (!_isAuthenticating && !_isLocked) {
        _backgroundedAt ??= widget.now();
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (_isLocked || _isAuthenticating || backgroundedAt == null) {
        return;
      }
      if (widget.now().difference(backgroundedAt) >
          widget.backgroundLockThreshold) {
        setState(() => _isLocked = true);
        unawaited(_authenticate());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SessionState>>(sessionProvider, (_, next) {
      final session = next.asData?.value;
      final lockState = ref.read(appLockStateProvider);
      final enabled = ref.read(biometricLockEnabledProvider);

      if (session is SessionUnauthenticated || lockState.isLoggingOut) {
        _resetLockState(markUnauthenticated: true);
        return;
      }

      if (session is SessionAuthenticated && !lockState.isLoggingOut) {
        if (!_coldStartHandled) {
          _coldStartHandled = true;
          if (!_sawUnauthenticated && enabled) {
            setState(() => _isLocked = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                unawaited(_authenticate());
              }
            });
          }
        }
      }
    });

    ref.listen<bool>(biometricLockEnabledProvider, (prev, next) {
      if (!next) {
        _resetLockState();
      } else if (prev == false && next == true) {
        // User just explicitly enabled lock from Profile after authenticating;
        // mark cold-start handled so the current session stays unlocked until
        // the next cold start or >30s background return.
        _coldStartHandled = true;
      }
    });

    ref.listen<AppLockState>(appLockStateProvider, (_, next) {
      if (next.isLoggingOut) {
        _resetLockState(markUnauthenticated: true);
      }
    });

    if (!_isLocked || !_isCurrentlyEligible()) {
      return widget.child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: PopScope(
            canPop: false,
            child: _AppLockOverlay(
              isAuthenticating: _isAuthenticating,
              onUnlockPressed: () => unawaited(_authenticate()),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppLockOverlay extends StatelessWidget {
  final bool isAuthenticating;
  final VoidCallback onUnlockPressed;

  const _AppLockOverlay({
    required this.isAuthenticating,
    required this.onUnlockPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingSemantic = theme.extension<AppSemanticColors>();
    final semantic = existingSemantic ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);

    Widget content = Material(
      color: semantic.canvas,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const BrandSignatureLogo(designPx: 72),
              const SizedBox(height: 24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: semantic.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 36,
                  color: semantic.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'التطبيق مقفل',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: semantic.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'يرجى تأكيد هويتك للمتابعة بأمان',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: semantic.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  key: const ValueKey('app_lock_unlock_button'),
                  onPressed: isAuthenticating ? null : onUnlockPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: semantic.primary,
                    foregroundColor: semantic.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: isAuthenticating
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              semantic.onPrimary,
                            ),
                          ),
                        )
                      : const Icon(Icons.face_rounded),
                  label: Text(
                    isAuthenticating
                        ? 'جاري التحقق...'
                        : 'فتح باستخدام Face ID',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (existingSemantic == null) {
      content = Theme(
        data: theme.copyWith(extensions: [semantic]),
        child: content,
      );
    }

    return AbsorbPointer(
      absorbing: false,
      child: content,
    );
  }
}
