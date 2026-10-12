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
  'coffee': Icons.coffee,
  'flight': Icons.flight,
  'train': Icons.train,
  'local_gas_station': Icons.local_gas_station,
  'bolt': Icons.bolt,
  'water_drop': Icons.water_drop,
  'wifi': Icons.wifi,
  'phone_android': Icons.phone_android,
  'fitness_center': Icons.fitness_center,
  'sports_esports': Icons.sports_esports,
  'music_note': Icons.music_note,
  'book': Icons.book,
  'pets': Icons.pets,
  'savings': Icons.savings,
  'card_giftcard': Icons.card_giftcard,
  'shopping_cart': Icons.shopping_cart,
};

IconData getIcon(String key) => categoryIcons[key] ?? Icons.category;

IconData getAccountIcon(String key) => accountIcons[key] ?? Icons.account_balance_wallet;

Color hexToColor(String hex) => Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
