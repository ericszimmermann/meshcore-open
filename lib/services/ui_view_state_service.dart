import 'package:flutter/foundation.dart';

import '../storage/prefs_manager.dart';
import '../utils/contact_search.dart';

const String? contactsAllGroupsValue = null;

class UiViewStateService extends ChangeNotifier {
  static const _keyContactsSortOption = 'ui_contacts_sort_option';
  static const _keyContactsShowUnreadOnly = 'ui_contacts_show_unread_only';
  static const _keyContactsTypeFilter = 'ui_contacts_type_filter';
  static const _keyChannelsSortIndex = 'ui_channels_sort_index';

  String? _contactsSelectedGroupName = contactsAllGroupsValue;
  String _contactsSearchText = '';
  bool _contactsSearchExpanded = false;
  ContactSortOption _contactsSortOption = ContactSortOption.lastSeen;
  bool _contactsShowUnreadOnly = false;
  ContactTypeFilter _contactsTypeFilter = ContactTypeFilter.all;

  String _channelsSearchText = '';
  int _channelsSortIndex = 0;

  String? get contactsSelectedGroupName => _contactsSelectedGroupName;
  String get contactsSearchText => _contactsSearchText;
  bool get contactsSearchExpanded => _contactsSearchExpanded;
  ContactSortOption get contactsSortOption => _contactsSortOption;
  bool get contactsShowUnreadOnly => _contactsShowUnreadOnly;
  ContactTypeFilter get contactsTypeFilter => _contactsTypeFilter;
  String get channelsSearchText => _channelsSearchText;
  int get channelsSortIndex => _channelsSortIndex;

  Future<void> initialize() async {
    final prefs = PrefsManager.instance;

    final sortStr = prefs.getString(_keyContactsSortOption);
    if (sortStr != null) {
      _contactsSortOption = ContactSortOption.values.firstWhere(
        (e) => e.name == sortStr,
        orElse: () => ContactSortOption.lastSeen,
      );
    }

    _contactsShowUnreadOnly =
        prefs.getBool(_keyContactsShowUnreadOnly) ?? false;

    final typeStr = prefs.getString(_keyContactsTypeFilter);
    if (typeStr != null) {
      _contactsTypeFilter = ContactTypeFilter.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => ContactTypeFilter.all,
      );
    }

    _channelsSortIndex = prefs.getInt(_keyChannelsSortIndex) ?? 0;
  }

  void setContactsSelectedGroupName(String? value) {
    if (_contactsSelectedGroupName == value) return;
    _contactsSelectedGroupName = value;
    notifyListeners();
  }

  void setContactsSearchText(String value) {
    if (_contactsSearchText == value) return;
    _contactsSearchText = value;
    notifyListeners();
  }

  void setContactsSearchExpanded(bool value) {
    if (_contactsSearchExpanded == value) return;
    _contactsSearchExpanded = value;
    notifyListeners();
  }

  void setContactsSortOption(ContactSortOption value) {
    if (_contactsSortOption == value) return;
    _contactsSortOption = value;
    notifyListeners();
    PrefsManager.instance.setString(_keyContactsSortOption, value.name);
  }

  void setContactsShowUnreadOnly(bool value) {
    if (_contactsShowUnreadOnly == value) return;
    _contactsShowUnreadOnly = value;
    notifyListeners();
    PrefsManager.instance.setBool(_keyContactsShowUnreadOnly, value);
  }

  void setContactsTypeFilter(ContactTypeFilter value) {
    if (_contactsTypeFilter == value) return;
    _contactsTypeFilter = value;
    notifyListeners();
    PrefsManager.instance.setString(_keyContactsTypeFilter, value.name);
  }

  void setChannelsSearchText(String value) {
    if (_channelsSearchText == value) return;
    _channelsSearchText = value;
    notifyListeners();
  }

  void setChannelsSortIndex(int value) {
    if (_channelsSortIndex == value) return;
    _channelsSortIndex = value;
    notifyListeners();
    PrefsManager.instance.setInt(_keyChannelsSortIndex, value);
  }
}
