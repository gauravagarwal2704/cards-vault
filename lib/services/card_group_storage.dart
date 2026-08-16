import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/card_group.dart';
import 'secure_card_storage.dart';

class CardGroupStorage {
  static final CardGroupStorage _instance = CardGroupStorage._internal();
  factory CardGroupStorage() => _instance;
  CardGroupStorage._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _groupsKey = 'card_groups';

  Future<List<CardGroup>> loadGroups() async {
    try {
      final String? json = await _secureStorage.read(key: _groupsKey);
      if (json == null) return [];

      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      final groups = decoded
          .map((e) => CardGroup.fromJson(e as Map<String, dynamic>))
          .toList();
      groups.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return groups;
    } catch (e) {
      return [];
    }
  }

  Future<CardGroup?> loadGroup(String groupId) async {
    final groups = await loadGroups();
    for (final group in groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  Future<CardGroup> createGroup(String name, {int? colorValue}) async {
    final group = CardGroup(
      id: const Uuid().v4(),
      name: name.trim(),
      colorValue: colorValue,
      createdAt: DateTime.now(),
    );

    final groups = await loadGroups();
    groups.add(group);
    await _persist(groups);
    return group;
  }

  Future<void> renameGroup(String groupId, String name) async {
    final groups = await loadGroups();
    final index = groups.indexWhere((g) => g.id == groupId);
    if (index == -1) return;

    groups[index] = groups[index].copyWith(name: name.trim());
    await _persist(groups);
  }

  /// Removes the group and detaches every card that referenced it, so no card is
  /// left pointing at a group that no longer exists.
  Future<void> deleteGroup(String groupId) async {
    final groups = await loadGroups();
    groups.removeWhere((g) => g.id == groupId);
    await _persist(groups);

    final cardStorage = SecureCardStorage();
    final cards = await cardStorage.loadCards();
    for (final card in cards) {
      if (card.groupId == groupId && card.id != null) {
        await cardStorage.updateCard(card.copyWith(clearGroup: true));
      }
    }
  }

  Future<void> deleteAllGroups() async {
    await _secureStorage.delete(key: _groupsKey);
  }

  /// Adds groups that are not already stored, keeping existing ones untouched.
  /// Used when restoring a backup onto a device that already has groups.
  Future<void> mergeGroups(List<CardGroup> groups) async {
    final merged = await loadGroups();
    final existingIds = merged.map((g) => g.id).toSet();
    for (final group in groups) {
      if (!existingIds.contains(group.id)) merged.add(group);
    }
    await _persist(merged);
  }

  Future<void> _persist(List<CardGroup> groups) async {
    await _secureStorage.write(
      key: _groupsKey,
      value: jsonEncode(groups.map((g) => g.toJson()).toList()),
    );
  }
}
