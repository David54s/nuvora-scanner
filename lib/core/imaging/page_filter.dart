/// Filtros que se pueden aplicar a una página ya recortada.
enum PageFilter {
  original('Original'),
  grayscale('Grises'),
  bw('B/N'),
  enhanced('Mejorado');

  const PageFilter(this.label);

  final String label;
}
