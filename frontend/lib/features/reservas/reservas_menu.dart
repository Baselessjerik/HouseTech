import 'package:flutter/material.dart';

import '../../../models/user_model.dart';
import 'pages/amenidades_admin_page.dart';
import 'pages/reservas_residente_page.dart';

/// Conecta los permisos del Módulo 3 con sus páginas en [AppShell].
class ReservasMenu {
  const ReservasMenu._();

  static Widget Function(UserModel)? paginaPara(String permiso) {
    switch (permiso) {
      case 'reservas.solicitar':
        return (_) => const ReservasResidentePage();
      case 'amenidades.gestionar':
        return (_) => const AmenidadesAdminPage();
      default:
        return null;
    }
  }
}

