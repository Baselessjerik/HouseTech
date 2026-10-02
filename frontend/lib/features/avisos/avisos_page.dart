import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/aviso_model.dart';
import '../../widgets/app_card.dart';

class AvisosPage extends StatelessWidget {
  final Set<int> leidos;
  final void Function(int) onMarcar;
  final VoidCallback onTodos;

  const AvisosPage({
    super.key,
    required this.leidos,
    required this.onMarcar,
    required this.onTodos,
  });

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Avisos y notificaciones',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
              ),
              TextButton(
                onPressed: leidos.length == avisos.length ? null : onTodos,
                child: const Text('Marcar leídos'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < avisos.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                onTap: () => onMarcar(i),
                borderColor: avisos[i].urgente
                    ? coralAlert.withOpacity(.4)
                    : Colors.black12,
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          (avisos[i].urgente ? coralAlert : primaryBlue)
                              .withOpacity(.15),
                      child: Icon(
                        avisos[i].urgente
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline,
                        color: avisos[i].urgente ? coralAlert : primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            avisos[i].titulo,
                            style: TextStyle(
                              fontWeight: leidos.contains(i)
                                  ? FontWeight.w500
                                  : FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            avisos[i].detalle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!leidos.contains(i))
                      const CircleAvatar(
                        radius: 5,
                        backgroundColor: coralAlert,
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
}