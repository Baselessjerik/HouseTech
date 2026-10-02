class Aviso {
  final String titulo, detalle;
  final bool urgente;

  const Aviso(this.titulo, this.detalle, {this.urgente = false});
}

const avisos = [
  Aviso('Corte de agua programado', 'Jueves 2 oct · 8:00 AM a 2:00 PM', urgente: true),
  Aviso('Asamblea ordinaria de copropietarios', '18 de octubre · Salón Social'),
  Aviso('Mantenimiento de piscina', 'Del 10 al 12 de octubre'),
];