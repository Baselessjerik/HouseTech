import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pqr_model.dart';
import '../models/aviso_model.dart';

class TabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

class PqrsNotifier extends Notifier<List<Pqr>> {
  @override
  List<Pqr> build() => const [
        Pqr(
          'PQR-2026-094',
          'Petición',
          'Mantenimiento preventivo luminaria pasillo piso 5',
          'Hoy · 08:30 AM',
          PqrEstado.recibido,
          descripcion:
              'La luminaria del pasillo del piso 5 parpadea desde hace una semana y requiere revisión preventiva.',
          historial: [
            (PqrEstado.enviado, 'Hoy · 08:30 AM'),
            (PqrEstado.recibido, 'Hoy · 08:42 AM')
          ],
        ),
        Pqr(
          'PQR-2026-089',
          'Queja',
          'Ruido excesivo en salón social fuera de horario',
          '01 Oct 2026 · 10:15 AM',
          PqrEstado.respondido,
          respuesta:
              'Estimada Lizeth, la administración ya se comunicó con el residente responsable y se procedió según el manual de convivencia.',
          descripcion:
              'El pasado fin de semana hubo música a alto volumen en el salón social después de las 11:00 PM.',
          historial: [
            (PqrEstado.enviado, '01 Oct · 10:15 AM'),
            (PqrEstado.recibido, '01 Oct · 10:20 AM'),
            (PqrEstado.visto, '01 Oct · 11:05 AM'),
            (PqrEstado.respondido, '01 Oct · 02:40 PM'),
          ],
        ),
      ];

  void agregar(Pqr p) => state = [p, ...state];
}

class LeidosNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => {};
  void marcar(int i) => state = {...state, i};
  void todos() => state = {for (int i = 0; i < avisos.length; i++) i};
}

final tabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);
final pqrsProvider = NotifierProvider<PqrsNotifier, List<Pqr>>(PqrsNotifier.new);
final leidosProvider = NotifierProvider<LeidosNotifier, Set<int>>(LeidosNotifier.new);