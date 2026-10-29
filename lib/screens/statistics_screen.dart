import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/statistics.dart';
import '../models/shelf.dart';

const _monthLetters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

/// Reading statistics, for all time or for one year, with a yearly goal.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({
    super.key,
    required this.repository,
    required this.settings,
  });

  final BookRepository repository;
  final AppSettings settings;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  int? _year;

  Future<void> _editGoal(int year, int? current) async {
    final controller = TextEditingController(text: current?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$year reading goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Books to read',
            helperText: 'Leave empty to remove the goal',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    widget.settings.setGoal(year, int.tryParse(controller.text.trim()));
  }

  Widget _goalCard(int year, BookStats stats) {
    final goal = widget.settings.goalFor(year);
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$year reading goal', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            if (goal == null)
              const Text('No goal set for this year.')
            else ...[
              LinearProgressIndicator(
                value: (stats.finishedCount / goal).clamp(0.0, 1.0).toDouble(),
              ),
              const SizedBox(height: 8),
              Text('${stats.finishedCount} of $goal books'),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _editGoal(year, goal),
                child: Text(goal == null ? 'Set a goal' : 'Change goal'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.repository, widget.settings]),
        builder: (context, _) {
          final books = widget.repository.books;
          if (books.isEmpty) {
            return const Center(child: Text('Add some books to see statistics.'));
          }
          final overall = computeStats(books);
          final selected = _year;
          final year =
              selected != null && overall.byYear.containsKey(selected)
                  ? selected
                  : null;
          final stats = year == null ? overall : computeStats(books, year: year);
          final average = stats.averageRating;
          final longest = stats.longest;
          final textTheme = Theme.of(context).textTheme;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (overall.byYear.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All time'),
                      selected: year == null,
                      onSelected: (_) => setState(() => _year = null),
                    ),
                    for (final y in overall.yearsNewestFirst)
                      ChoiceChip(
                        label: Text('$y'),
                        selected: year == y,
                        onSelected: (_) => setState(() => _year = y),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatTile(
                    label: 'Books finished',
                    value: stats.finishedCount.toString(),
                  ),
                  _StatTile(
                    label: 'Pages read',
                    value: stats.pagesRead.toString(),
                  ),
                  _StatTile(
                    label: 'Average rating',
                    value: average == null ? '–' : average.toStringAsFixed(1),
                  ),
                  _StatTile(
                    label: 'Average pages',
                    value: stats.averagePages?.toString() ?? '–',
                  ),
                  if (longest != null)
                    _StatTile(
                      label: 'Longest book',
                      value: '${longest.pages} pages',
                      detail: longest.title,
                    ),
                ],
              ),
              if (year != null) ...[
                const SizedBox(height: 24),
                _goalCard(year, stats),
              ],
              if (year == null) ...[
                const SizedBox(height: 24),
                Text('By shelf', style: textTheme.titleMedium),
                for (final shelf in Shelf.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(shelf.label)),
                        Text('${stats.shelfCounts[shelf] ?? 0}'),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              if (year == null && overall.byYear.isNotEmpty) ...[
                Text('Books finished per year', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                _BarChart(
                  labels: [for (final y in overall.byYear.keys) '$y'],
                  values: overall.byYear.values.toList(),
                ),
              ] else if (year != null) ...[
                Text(
                  'Books finished per month in $year',
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _BarChart(labels: _monthLetters, values: stats.byMonth),
              ],
              if (overall.finishedWithoutDate > 0) ...[
                const SizedBox(height: 24),
                Text(
                  '${overall.finishedWithoutDate} finished '
                  '${overall.finishedWithoutDate == 1 ? 'book has' : 'books have'}'
                  ' no finish date, so they are left out of the yearly and '
                  'monthly charts. Open a book to set its finish date.',
                  style: textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final detail = this.detail;
    return Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label, style: textTheme.bodySmall),
              if (detail != null)
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.labels, required this.values});

  final List<String> labels;
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(0, (max, value) => value > max ? value : max);
    final color = Theme.of(context).colorScheme.primary;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      values[i] == 0 ? '' : values[i].toString(),
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: maxValue == 0 ? 0 : 110 * values[i] / maxValue,
                      child: ColoredBox(color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
