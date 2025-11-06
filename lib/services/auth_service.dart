import '../models/login_details.dart';
import '../repositories/repository_interface.dart';

class AuthService {
  final RepositoryInterface repository;
  LoginDetails? _currentUser;

  AuthService(this.repository);

  LoginDetails? get currentUser => _currentUser;

  bool get isAuthenticated => _currentUser != null;

  Future<bool> login(String username, String password) async {
    try {
      final loginDetails = await repository.getLoginDetailsByUsername(username);
      
      if (loginDetails == null) {
        print('Login failed: User not found: $username');
        return false;
      }

      if (loginDetails.password != password) {
        print('Login failed: Incorrect password for user: $username');
        return false;
      }

      if (!loginDetails.isActive) {
        print('Login failed: User account is inactive: $username');
        return false;
      }

      _currentUser = loginDetails;
      print('Login successful: ${loginDetails.displayName}');
      return true;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  void logout() {
    _currentUser = null;
  }

  String? getCurrentUserId() {
    return _currentUser?.loginDetailsId;
  }

  String? getCurrentUserDisplayName() {
    return _currentUser?.displayName;
  }
}

