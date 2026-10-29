import 'dart:io';

import 'package:flutter/material.dart';

/// A cover from the phone's photos or the web, or a plain placeholder when
/// there is none. A cover picked from the phone wins over the web cover.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    this.coverUrl,
    this.coverPath,
    this.width = 44,
    this.height = 64,
  });

  final String? coverUrl;
  final String? coverPath;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.menu_book)),
      ),
    );
    final path = coverPath;
    final url = coverUrl;
    final Widget image;
    if (path != null) {
      image = Image.file(
        File(path),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    } else if (url != null) {
      image = Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    } else {
      return placeholder;
    }
    return ClipRRect(borderRadius: BorderRadius.circular(4), child: image);
  }
}
