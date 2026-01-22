
// lib/features/pos/domain/models/customer_model.dart
class CustomerModel {
  final String id;
  final String fullName;
  final String? phone;
  final String? iin;
  final String? comment;

  const CustomerModel({
    required this.id,
    required this.fullName,
    this.phone,
    this.iin,
    this.comment,
  });
}
