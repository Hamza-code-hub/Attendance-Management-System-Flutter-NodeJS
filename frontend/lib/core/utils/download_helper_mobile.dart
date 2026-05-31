void triggerCsvDownload(List<int> bytes, String filename) {
  // On Android/iOS, saving a CSV is done via file sharing or storage.
  // The audit logs export is an admin-only feature used on web.
  // No-op on mobile — the caller shows a snackbar if needed.
}
