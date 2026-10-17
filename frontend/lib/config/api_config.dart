class ApiConfig {
  static const baseUrl = 'http://127.0.0.1:8000/api/v1';
  static const loginUrl = '$baseUrl/auth/login/';
  static const registroUrl = '$baseUrl/auth/registro/';
  static const recuperarPasswordUrl = '$baseUrl/auth/recuperar/';
  static const validarCodigoPasswordUrl = '$baseUrl/auth/validar-codigo/';
  static const restablecerPasswordUrl = '$baseUrl/auth/restablecer/';
}
