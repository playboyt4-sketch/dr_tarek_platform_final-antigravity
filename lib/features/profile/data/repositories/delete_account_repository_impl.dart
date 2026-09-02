import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/repositories/delete_account_repository.dart';

class DeleteAccountRepositoryImpl implements DeleteAccountRepository {
  final FirebaseFunctions functions;

  DeleteAccountRepositoryImpl({
    FirebaseFunctions? functions,
  }) : functions = functions ?? FirebaseFunctions.instance;

  @override
  Future<DeleteAccountResult> deleteMyAccount({
    required String password,
  }) async {
    try {
      final callable = functions.httpsCallable('deleteMyAccount');
      final result = await callable.call({'password': password});

      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] == true) {
        final deletedMap = Map<String, dynamic>.from(data['deleted'] ?? {});
        final counts = <String, int>{};
        deletedMap.forEach((key, value) {
          counts[key] = value is int ? value : 0;
        });
        return DeleteAccountResult(counts);
      }

      throw Failure(
        FailureCode.unknown,
        debugDetail: 'Server returned success=false',
      );
    } on FirebaseFunctionsException catch (e, stackTrace) {
      throw Failure.from(e, stackTrace);
    } catch (e, stackTrace) {
      if (e is Failure) rethrow;
      throw Failure(
        FailureCode.unknown,
        debugDetail: e.toString(),
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }
}