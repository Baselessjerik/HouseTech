import 'dart:convert';
import 'dart:typed_data';

class UserModel {
  const UserModel({
    required this.id,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.nombres,
    required this.apellidos,
    required this.username,
    required this.email,
    required this.telefono,
    required this.activo,
    required this.roles,
    required this.permisos,
    this.fotoPerfil,
    this.ultimoLogin,
  });

  final int id;
  final String tipoDocumento;
  final String numeroDocumento;
  final String nombres;
  final String apellidos;
  final String username;
  final String email;
  final String? telefono;
  final bool activo;
  final List<String> roles;
  final List<String> permisos;
  final String? fotoPerfil;
  final String? ultimoLogin;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      tipoDocumento: json['tipo_documento'] as String? ?? '',
      numeroDocumento: json['numero_documento'] as String? ?? '',
      nombres: json['nombres'] as String? ?? '',
      apellidos: json['apellidos'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      telefono: json['telefono'] as String?,
      activo: json['activo'] as bool? ?? false,
      roles: List<String>.from(json['roles'] as List? ?? const []),
      permisos: List<String>.from(json['permisos'] as List? ?? const []),
      fotoPerfil: json['foto_perfil'] as String?,
      ultimoLogin: json['ultimo_login'] as String?,
    );
  }

  Uint8List? get fotoBytes {
    final raw = fotoPerfil;
    if (raw == null || raw.isEmpty) return null;
    final commaIdx = raw.indexOf(',');
    final b64 = commaIdx >= 0 ? raw.substring(commaIdx + 1) : raw;
    try {
      return base64Decode(b64.replaceAll(RegExp(r'\s+'), ''));
    } catch (_) {
      return null;
    }
  }

  String get nombreCompleto => '$nombres $apellidos'.trim();

  String get iniciales {
    final first = nombres.isNotEmpty ? nombres[0] : '';
    final last = apellidos.isNotEmpty ? apellidos[0] : '';
    return '$first$last'.toUpperCase();
  }

  bool tienePermiso(String permiso) => permisos.contains(permiso);

  String get rolesVisibles => roles.map(nombreRol).join(' · ');

  static String nombreRol(String codigo) {
    switch (codigo) {
      case 'ADMIN':
        return 'Administrador';
      case 'RESIDENTE':
        return 'Residente';
      case 'RESPONSABLE_PQR':
        return 'Responsable de PQR';
      default:
        return codigo;
    }
  }
}
