import 'app_settings.dart';
import 'book_repository.dart';
import 'phone_sync_core.dart';
import 'profiles.dart';
import 'sync_profiles.dart';
import 'sync_server.dart';

/// A profile's library and settings, opened for a sync while another
/// profile is open on the phone.
typedef OpenedProfile = ({BookRepository repository, AppSettings settings});

/// Lets a PC sync every profile on this phone with one pairing. The open
/// profile syncs with the library on the screen; another profile's library
/// is opened in the background. A profile with a PIN syncs only while it
/// is open, so its books never leave the phone without the PIN.
class PhoneProfileHost implements SyncProfileHost {
  PhoneProfileHost({
    required this.store,
    required this.openCore,
    required this.open,
  });

  final ProfileStore store;

  /// The sync of the profile that is open on the phone.
  final PhoneSyncCore openCore;

  /// Opens another profile's library and settings.
  final Future<OpenedProfile> Function(String id) open;

  final _cores = <String, Future<PhoneSyncCore>>{};

  String get _openId => store.active.id;

  bool _locked(String id) => id != _openId && store.hasPin(id);

  List<SyncProfileInfo> list() => [
        for (final profile in store.profiles)
          SyncProfileInfo(
            id: profile.id,
            name: profile.name,
            color: profile.color,
            locked: _locked(profile.id),
          ),
      ];

  @override
  Future<String> profiles(String body) async {
    for (final wanted in decodeProfileRequest(body)) {
      if (store.profiles.length >= maxSyncProfiles) break;
      if (store.nameProblem(wanted.name) != null) continue;
      final profile = await store.add(wanted.name);
      if (profileColors.contains(wanted.color)) {
        await store.setColor(profile.id, wanted.color);
      }
    }
    return encodeProfileList(list());
  }

  @override
  Future<SyncEndpoint?> endpoint(String id) async {
    if (store.byId(id) == null) {
      _cores.remove(id);
      return null;
    }
    if (id == _openId) return openCore;
    if (_locked(id)) throw const ProfileLocked();
    final opening = _cores[id] ??= () async {
      final opened = await open(id);
      return PhoneSyncCore(
        repository: opened.repository,
        settings: opened.settings,
      );
    }();
    try {
      return await opening;
    } catch (_) {
      _cores.remove(id);
      rethrow;
    }
  }
}
