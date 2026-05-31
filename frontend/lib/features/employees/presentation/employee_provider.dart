import 'dart:convert';
import '../../../core/config/server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../authentication/presentation/auth_state.dart';

class Employee {
  final int id;
  final String employeeCode;
  final String firstName;
  final String lastName;
  final String phone;
  final String designation;
  final int? departmentId;
  final int? shiftId;
  final String joiningDate;
  final String employmentStatus;
  final String? departmentName;
  final String? shiftName;

  Employee({
    required this.id,
    required this.employeeCode,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.designation,
    this.departmentId,
    this.shiftId,
    required this.joiningDate,
    required this.employmentStatus,
    this.departmentName,
    this.shiftName,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as int,
      employeeCode: json['employeeCode'] as String,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      phone: json['phone'] ?? '',
      designation: json['designation'] ?? '',
      departmentId: json['departmentId'] as int?,
      shiftId: json['shiftId'] as int?,
      joiningDate: json['joiningDate'] as String,
      employmentStatus: json['employmentStatus'] as String,
      departmentName: json['departmentName'] as String?,
      shiftName: json['shiftName'] as String?,
    );
  }
}

class EmployeeNotifier extends StateNotifier<AsyncValue<List<Employee>>> {
  final Ref _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/employees';

  EmployeeNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchEmployees();
  }

  Map<String, String> _getHeaders() {
    final auth = _ref.read(authProvider);
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${auth.accessToken ?? ''}',
    };
  }

  /**
   * Fetch employee list
   */
  Future<void> fetchEmployees() async {
    try {
      state = const AsyncValue.loading();
      final response = await http.get(Uri.parse(_baseUrl), headers: _getHeaders());

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        final list = (resBody['data'] as List).map((x) => Employee.fromJson(x)).toList();
        state = AsyncValue.data(list);
      } else {
        state = AsyncValue.error(resBody['error']?['message'] ?? 'Failed to load employees', StackTrace.current);
      }
    } catch (e, st) {
      state = AsyncValue.error('Network connection error.', st);
    }
  }

  /**
   * Create new employee profile
   */
  Future<bool> createEmployee(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: _getHeaders(),
        body: jsonEncode(data),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 201 && resBody['success'] == true) {
        await fetchEmployees();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /**
   * Update employee details
   */
  Future<bool> updateEmployee(int id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/$id'),
        headers: _getHeaders(),
        body: jsonEncode(data),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        await fetchEmployees();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

// Me profile details provider
class MyProfileNotifier extends StateNotifier<AsyncValue<Employee?>> {
  final Ref _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/employees/me';

  MyProfileNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchProfile();
  }

  Future<void> fetchProfile() async {
    try {
      state = const AsyncValue.loading();
      final auth = _ref.read(authProvider);
      
      final response = await http.get(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.accessToken ?? ''}',
        },
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        state = AsyncValue.data(Employee.fromJson(resBody['data']));
      } else {
        state = AsyncValue.error(resBody['error']?['message'] ?? 'Failed to load profile', StackTrace.current);
      }
    } catch (e, st) {
      state = AsyncValue.error('Network connection error.', st);
    }
  }
}

// Global Providers
final employeesProvider = StateNotifierProvider<EmployeeNotifier, AsyncValue<List<Employee>>>((ref) {
  return EmployeeNotifier(ref);
});

final myProfileProvider = StateNotifierProvider<MyProfileNotifier, AsyncValue<Employee?>>((ref) {
  return MyProfileNotifier(ref);
});
