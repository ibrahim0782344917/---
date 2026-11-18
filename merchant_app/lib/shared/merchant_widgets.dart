import 'package:flutter/material.dart';

const merchantPurple = Color(0xFF01BE5F);
const merchantOrange = Color(0xFFF2AB3A);
const merchantCanvas = Color(0xFFF6F8F7);
const merchantDark = Color(0xFF163E32);

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
