import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SortField {
  dateAdded,
  title,
  author,
  rating,
  pages,
  dateFinished,
  format,
  favorite,
}

extension SortFieldLabel on SortField {
  String get label => switch (this) {
        SortField.dateAdded => 'Date added',
        SortField.title => 'Title',
        SortField.author => 'Author',
        SortField.rating => 'Rating',
        SortField.pages => 'Pages',
        SortField.dateFinished => 'Date finished',
        SortField.format => 'Format',
        SortField.favorite => 'Favorites first',
      };
}

enum DisplayMode { list, grid }

/// How the library is sorted and shown, the app's accent colour and font,
/// and yearly reading goals. Saved on the phone with shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings({this.prefs});

  /// Brown, the colour Chapterly starts with.
  static const int defaultAccent = 0xFF795548;

  final SharedPreferences? prefs;
  SortField _sortField = SortField.dateAdded;
  bool _ascending = false;
  DisplayMode _display = DisplayMode.list;
  int _accent = defaultAccent;
  String? _fontFamily;
  int? _monthlyGoal;
  final Map<int, int> _goals = {};

  SortField get sortField => _sortField;
  bool get ascending => _ascending;
  DisplayMode get display => _display;

  /// The accent colour as a 0xAARRGGBB number.
  int get accent => _accent;

  /// The name of a font on the phone, or null for the app's normal font.
  String? get fontFamily => _fontFamily;

  /// Books to finish every month, or null for no monthly goal.
  int? get monthlyGoal => _monthlyGoal;

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
    settings._accent = prefs.getInt('accent') ?? defaultAccent;
    settings._fontFamily = prefs.getString('font');
    settings._monthlyGoal = prefs.getInt('monthly_goal');
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
      _ascending = field == SortField.title ||
          field == SortField.author ||
          field == SortField.format;
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

  void setAccent(int colorValue) {
    _accent = colorValue;
    _save();
    notifyListeners();
  }

  /// Pass null to go back to the app's normal font.
  void setFontFamily(String? family) {
    _fontFamily = family;
    _save();
    notifyListeners();
  }

  /// A null or zero goal removes the monthly goal.
  void setMonthlyGoal(int? goal) {
    if (goal == null || goal <= 0) {
      _monthlyGoal = null;
      prefs?.remove('monthly_goal');
    } else {
      _monthlyGoal = goal;
      prefs?.setInt('monthly_goal', goal);
    }
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
    prefs?.setInt('accent', _accent);
    final font = _fontFamily;
    if (font == null) {
      prefs?.remove('font');
    } else {
      prefs?.setString('font', font);
    }
  }
}
