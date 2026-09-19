class CrashJournal {
  const CrashJournal._();

  static Future<CrashJournal> create() async => const CrashJournal._();

  bool writeSync(Map<String, dynamic> record) => true;

  Future<List<Map<String, dynamic>>> read() async => const [];

  Future<void> clear() async {}
}
