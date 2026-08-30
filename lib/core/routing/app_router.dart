import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/domain/entities/session_state.dart';
import '../../features/authentication/presentation/providers/session_provider.dart';
import '../../features/authentication/presentation/screens/auth_gate.dart';

class AppRouter extends ConsumerWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<SessionState>>(sessionProvider, (_, next) {
      final session = next is AsyncData<SessionState> ? next.value : null;
      if (session == null ||
          session is SessionAuthenticated ||
          session is SessionInitializing) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        
        void performPop() {
          if (!context.mounted) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
        }

        final route = ModalRoute.of(context);
        if (route?.animation != null && !route!.animation!.isCompleted) {
          late final AnimationStatusListener listener;
          listener = (status) {
            if (status == AnimationStatus.completed) {
              route.animation!.removeStatusListener(listener);
              performPop();
            }
          };
          route.animation!.addStatusListener(listener);
        } else {
          performPop();
        }
      });
    });

    final sessionState = ref.watch(sessionProvider);
    return AuthGate(sessionState: sessionState);
  }
}
