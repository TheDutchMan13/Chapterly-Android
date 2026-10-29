import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/open_library_client.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'shelf_picker.dart';

/// Search Open Library and add results to a shelf.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.repository,
    required this.client,
  });

  final BookRepository repository;
  final OpenLibraryClient client;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<OpenLibraryBook> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.client.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach Open Library. '
            'Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(OpenLibraryBook result) async {
    final shelf = await showShelfPicker(context);
    if (shelf == null || !mounted) return;
    await widget.repository.add(
      title: result.title,
      author: result.author,
      shelf: shelf,
      isbn: result.isbn,
      coverUrl: result.coverUrl,
      firstPublishYear: result.firstPublishYear,
      pages: result.pages,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "${result.title}" to ${shelf.label}')),
    );
  }

  Widget _buildResults() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }
    if (!_searched) {
      return const Center(child: Text('Search by title, author or ISBN.'));
    }
    if (_results.isEmpty) {
      return const Center(child: Text('No books found.'));
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return ListTile(
          leading: BookCover(coverUrl: result.coverUrl),
          title: Text(result.title),
          subtitle: Text(result.subtitle),
          trailing: const Icon(Icons.add),
          onTap: () => _add(result),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Open Library')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Title, author or ISBN',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search',
                  onPressed: _search,
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }
}
