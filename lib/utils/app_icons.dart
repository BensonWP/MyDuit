import 'package:flutter/material.dart';

const Map<String, IconData> accountIcons = {
  'cash': Icons.money,
  'bank': Icons.account_balance,
  'ewallet': Icons.phone_iphone,
  'card': Icons.credit_card,
};

const Map<String, IconData> categoryIcons = {
  'restaurant': Icons.restaurant,
  'directions_car': Icons.directions_car,
  'receipt': Icons.receipt,
  'shopping_bag': Icons.shopping_bag,
  'local_hospital': Icons.local_hospital,
  'school': Icons.school,
  'movie': Icons.movie,
  'work': Icons.work,
  'laptop': Icons.laptop,
  'more_horiz': Icons.more_horiz,
};

IconData getIcon(String key) => categoryIcons[key] ?? Icons.category;

IconData getAccountIcon(String key) => accountIcons[key] ?? Icons.account_balance_wallet;
