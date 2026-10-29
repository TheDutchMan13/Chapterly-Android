import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SortField { dateAdded, title, author, rating, pages, dateFinished }

extension SortFieldLabel on SortField {
  String get label => switch (this) {
        SortField.dateAdded => 'Date added',
        SortField.title => 'Title',
        SortField.author => 'Author',
        SortField.rating => 'Rating',
        SortField.pages => 'Pages',
        SortField.dateFinished => 'Date finished',
      };
}

enum DisplayMode { list, grid }

/// How the library is sorted and shown, plus yearly reading goals.
/// Saved on the phone with shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings({this.prefs});

  final SharedPreferences? prefs;
  SortField _sortField = SortField.dateAdded;
  bool _ascending = false;
  DisplayMode _display = DisplayMode.list;
  final Map<int, int> _goals = {};

  SortField get sortField => _sortField;
  bool get ascending => _ascending;
  DisplayMode get display => _display;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(prefs: prefs);
    settings._sortField =
        SortField.values.asNameMap()[prefs.getString('sortField')] ??
            SortField.dateAdded;
    settings._ascending = prefs.getBool('ascending') ?? false;
    settings._display =
        DisplayMode.values.asNameMap()[prefs.getString('display')] ??
            DisplayMode.list;
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('goal_')) continue;
      final year = int.tryParse(key.substring(5));
      final goal = prefs.getInt(key);
      if (year != null && goal != null) settings._goals[year] = goal;
    }
    return settings;
  }

  /// Choosing the field that is already selected flips the direction.
  void setSort(SortField field) {
    if (field == _sortField) {
      _ascending = !_ascending;
    } else {
      _sortField = field;
      _ascending = field == SortField.title || field == SortField.author;
    }
    _save();
    notifyListeners();
  }

  void toggleDisplay() {
    _display =
        _display == DisplayMode.list ? DisplayMode.grid : DisplayMode.list;
    _save();
    notifyListeners();
  }

  int? goalFor(int year) => _goals[year];

  /// A null or zero goal removes the goal for that year.
  void setGoal(int year, int? goal) {
    if (goal == null || goal <= 0) {
      _goals.remove(year);
      prefs?.remove('goal_$year');
    } else {
      _goals[year] = goal;
      prefs?.setInt('goal_$year', goal);
    }
    notifyListeners();
  }

  void _save() {
    prefs?.setString('sortField', _sortField.name);
    prefs?.setBool('ascending', _ascending);
    prefs?.setString('display', _display.name);
  }
}
