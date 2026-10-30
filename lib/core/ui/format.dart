String _two(int n) => n.toString().padLeft(2, '0');

/// `29/10/2026 17:05`
String formatDateTime(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

/// Título por defecto de un escaneo: `Escaneo 2026-10-29 17:05`.
String defaultScanTitle(DateTime d) =>
    'Escaneo ${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

String pagesLabel(int n) => n == 1 ? '1 página' : '$n páginas';
