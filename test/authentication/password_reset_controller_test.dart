import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/errors/failure.dart';
import 'package:dr_tarek_platform/features/authentication/domain/repositories/password_reset_repository.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/password_reset_provider.dart';

class _FakePasswordResetRepository implements PasswordResetRepository {
  int calls = 0;
  String? lastPhone;
  Future<void> Function(String phone)? onSubmit;

  @override
  Future<void> submitPasswordResetRequest({required String phoneNumber}) async {
    calls++;
    lastPhone = phoneNumber;
    if (onSubmit != null) await onSubmit!(phoneNumber);
  }
}

void main() {
  test('submit returns true and forwards the phone number', () async {
    final fake = _FakePasswordResetRepository();
    final container = ProviderContainer(
      overrides: [passwordResetRepositoryProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    final submitted = await container
        .read(passwordResetControllerProvider.notifier)
        .submit(phoneNumber: '01012345678');

    expect(submitted, isTrue);
    expect(fake.calls, 1);
    expect(fake.lastPhone, '01012345678');
    expect(container.read(passwordResetControllerProvider).value, isTrue);
  });

  test('concurrent duplicate submissions are ignored', () async {
    final gate = Completer<void>();
    final fake = _FakePasswordResetRepository()..onSubmit = (_) => gate.future;
    final container = ProviderContainer(
      overrides: [passwordResetRepositoryProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(passwordResetControllerProvider.notifier);
    final first = notifier.submit(phoneNumber: '01012345678');
    final second = await notifier.submit(phoneNumber: '01012345678');

    expect(second, isFalse);
    expect(fake.calls, 1);

    gate.complete();
    expect(await first, isTrue);
    expect(fake.calls, 1);
  });

  test('backend failure propagates as Failure for friendly mapping', () async {
    final fake = _FakePasswordResetRepository()
      ..onSubmit = (_) async {
        throw const Failure(FailureCode.tooManyRequests);
      };
    final container = ProviderContainer(
      overrides: [passwordResetRepositoryProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(passwordResetControllerProvider.notifier)
          .submit(phoneNumber: '01012345678'),
      throwsA(isA<Failure>()),
    );
    expect(container.read(passwordResetControllerProvider).hasError, isTrue);
  });
}
