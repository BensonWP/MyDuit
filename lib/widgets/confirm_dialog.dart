import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Snackbar "Urungkan" setelah hapus: [message] + aksi undo.
/// [onUndo] dibungkus try/catch — kegagalan restore (mis. FK) tampil
/// sebagai pesan error, bukan crash.
void showUndoBar(
  BuildContext context,
  String message,
  Future<void> Function() onUndo,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Urungkan',
        onPressed: () async {
          try {
            await onUndo();
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Gagal mengembalikan data'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        },
      ),
    ),
  );
}

/// Dialog konfirmasi gaya SweetAlert: ikon lingkaran merah, judul,
/// deskripsi, tombol Batal + Hapus. Return true bila pengguna lanjut.
Future<bool> confirmDelete(
  BuildContext context,
  String title, {
  String? description,
  String confirmLabel = 'Hapus',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(D.s6, D.s6, D.s6, 0),
      actionsPadding: const EdgeInsets.fromLTRB(D.s4, D.s3, D.s4, D.s4),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: D.expense.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: D.expense, size: 28),
          ),
          const SizedBox(height: D.s3),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
          if (description != null) ...[
            const SizedBox(height: D.s2),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: D.inkMuted, height: 1.5),
            ),
          ],
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: D.ink,
                  side: const BorderSide(color: D.line),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.rMd)),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(width: D.s3),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: D.expense,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.rMd)),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return result == true;
}
