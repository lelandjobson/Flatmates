import 'package:flutter/foundation.dart';

class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  User copyWith({
    String? id,
    String? name,
    String? email,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
    );
  }
}

class UserProvider extends ChangeNotifier {
  User _user = const User(
    id: 'demo-user',
    name: 'Scene Friend',
    email: 'scene.friend@example.com',
  );

  User get user => _user;

  void updateUser(User user) {
    _user = user;
    notifyListeners();
  }

  void updateName(String name) {
    _user = _user.copyWith(name: name);
    notifyListeners();
  }

  void updateEmail(String email) {
    _user = _user.copyWith(email: email);
    notifyListeners();
  }
}

