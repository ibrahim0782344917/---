import 'package:flutter/material.dart';

const merchantPurple = Color(0xFF17583D);
const merchantOrange = Color(0xFFC49B45);
const merchantCanvas = Color(0xFFF7F9F5);
const merchantDark = Color(0xFF17372B);

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
