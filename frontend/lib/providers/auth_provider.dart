import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';

class AuthSessionNotifier extends Notifier<UserModel?> {
  @override
  UserModel? build() => null;

  void setUser(UserModel user) => state = user;
  void clear() => state = null;
}

final authSessionProvider =
    NotifierProvider<AuthSessionNotifier, UserModel?>(AuthSessionNotifier.new);

final currentUserProvider = Provider<UserModel?>(
  (ref) => ref.watch(authSessionProvider),
);
