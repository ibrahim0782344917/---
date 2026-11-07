import 'package:flutter/material.dart';

const merchantPurple = Color(0xFF51159B);
const merchantOrange = Color(0xFFFF851B);
const merchantCanvas = Color(0xFFF8F5FD);
const merchantDark = Color(0xFF2A0D55);

String priceText(int value) {
  final formatted = value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]},',
  );
  return '$formatted د.ع';
}

Widget productPhoto(String? imageUrl, {double height = 100}) {
  if (imageUrl == null || !imageUrl.startsWith('https://')) {
    return SizedBox(
      height: height,
      child: const Center(
        child: Icon(Icons.inventory_2_outlined,
          size: 45, color: merchantPurple),
      ),
    );
  }
  return Image.network(
    imageUrl,
    height: height,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) => SizedBox(
      height: height,
      child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
    ),
  );
}
