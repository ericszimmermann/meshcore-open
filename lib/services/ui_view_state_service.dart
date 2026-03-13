import 'package:flutter/foundation.dart';

import '../widgets/list_filter_widget.dart';

const contactsAllGroupsValue = '__all__';

class UiViewStateService extends ChangeNotifier {
  String _contactsSelectedGroupName = contactsAllGroupsValue;
  String _contactsSearchText = '';
  bool _contactsSearchExpanded = false;
  ContactSortOption _contactsSortOption = ContactSortOption.lastSeen;
  bool _contactsShowUnreadOnly = false;
  ContactTypeFilter _contactsTypeFilter = ContactTypeFilter.all;

  String _channelsSearchText = '';
  int _channelsSortIndex = 0;

  String get contactsSelectedGroupName => _contactsSelectedGroupName;
  String get contactsSearchText => _contactsSearchText;
  bool get contactsSearchExpanded => _contactsSearchExpanded;
  ContactSortOption get contactsSortOption => _contactsSortOption;
  bool get contactsShowUnreadOnly => _contactsShowUnreadOnly;
  ContactTypeFilter get contactsTypeFilter => _contactsTypeFilter;
  String get channelsSearchText => _channelsSearchText;
  int get channelsSortIndex => _channelsSortIndex;

  void setContactsSelectedGroupName(String value) {
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
  }

  void setContactsShowUnreadOnly(bool value) {
    if (_contactsShowUnreadOnly == value) return;
    _contactsShowUnreadOnly = value;
    notifyListeners();
  }

  void setContactsTypeFilter(ContactTypeFilter value) {
    if (_contactsTypeFilter == value) return;
    _contactsTypeFilter = value;
    notifyListeners();
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
  }
}
