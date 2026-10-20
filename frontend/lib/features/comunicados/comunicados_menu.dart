import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import 'pages/bloqueos_admin_page.dart';
import 'pages/comunicados_admin_page.dart';
import 'pages/comunicados_residente_page.dart';

/// Páginas del Módulo 2 para el menú del shell, según el permiso que las habilita.
/// El shell solo consulta este mapa (una línea de integración, marcada // MODULO-2).
class ComunicadosMenu {
  static const permisoVer = 'comunicados.ver';
  static const permisoGestionar = 'comunicados.gestionar';
  static const permisoBloqueos = 'bloqueos.gestionar';

  /// Devuelve la pantalla del módulo para un permiso, o null si ese permiso no es de este módulo.
  static Widget Function(UserModel user)? paginaPara(String permiso) {
    switch (permiso) {
      case permisoVer:
        return (_) => const ComunicadosResidentePage();
      case permisoGestionar:
        return (_) => const ComunicadosAdminPage();
      case permisoBloqueos:
        return (_) => const BloqueosAdminPage();
      default:
        return null;
    }
  }
}
