import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';

class BookCover extends StatelessWidget {
  final Book book;
  const BookCover({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final cover = book.coverPath;
    if (cover != null && File(cover).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(cover),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(context),
        ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    const colors = [
      Color(0xFF00897B),
      Color(0xFF3949AB),
      Color(0xFF6D4C41),
      Color(0xFF455A64),
      Color(0xFFC62828),
    ];
    final color = colors[book.title.hashCode.abs() % colors.length];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.82), color],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            switch (book.type) {
              BookType.txt => Icons.article_outlined,
              BookType.pdf => Icons.picture_as_pdf_outlined,
              _ => Icons.photo_outlined,
            },
            color: Colors.white70,
            size: 30,
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
