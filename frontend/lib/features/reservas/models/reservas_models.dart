// Modelos de datos del Módulo 3 (Amenidades, Reservas, Agenda y Reportes).

DateTime? _dt(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

const diasSemanaNombres = <int, String>{
  1: 'Lunes',
  2: 'Martes',
  3: 'Miércoles',
  4: 'Jueves',
  5: 'Viernes',
  6: 'Sábado',
  7: 'Domingo',
};

class AmenidadHorarioModel {
  const AmenidadHorarioModel({
    required this.diaSemana,
    required this.horaApertura,
    required this.horaCierre,
    this.activo = true,
  });

  final int diaSemana;
  final String horaApertura;
  final String horaCierre;
  final bool activo;

  String get diaNombre => diasSemanaNombres[diaSemana] ?? 'Día $diaSemana';

  static String _hhmm(String raw) => raw.length >= 5 ? raw.substring(0, 5) : raw;

  factory AmenidadHorarioModel.fromJson(Map<String, dynamic> j) => AmenidadHorarioModel(
        diaSemana: j['dia_semana'] as int? ?? 1,
        horaApertura: _hhmm(j['hora_apertura'] as String? ?? '08:00'),
        horaCierre: _hhmm(j['hora_cierre'] as String? ?? '20:00'),
        activo: j['activo'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'dia_semana': diaSemana,
        'hora_apertura': horaApertura,
        'hora_cierre': horaCierre,
        'activo': activo,
      };
}

class ReglaReservaModel {
  const ReglaReservaModel({
    this.duracionMinMinutos = 30,
    this.duracionMaxMinutos = 240,
    this.anticipacionMinHoras = 1,
    this.anticipacionMaxDias = 30,
    this.maxReservasMesInmueble,
    this.horasLimiteCancelacion = 24,
    this.requiereConfirmacion = true,
    this.horasLimiteConfirmacion = 24,
    this.horasRecordatorio = 24,
    this.observaciones,
  });

  final int duracionMinMinutos;
  final int duracionMaxMinutos;
  final int anticipacionMinHoras;
  final int anticipacionMaxDias;
  final int? maxReservasMesInmueble;
  final int horasLimiteCancelacion;
  final bool requiereConfirmacion;
  final int horasLimiteConfirmacion;
  final int horasRecordatorio;
  final String? observaciones;

  factory ReglaReservaModel.fromJson(Map<String, dynamic> j) => ReglaReservaModel(
        duracionMinMinutos: j['duracion_min_minutos'] as int? ?? 30,
        duracionMaxMinutos: j['duracion_max_minutos'] as int? ?? 240,
        anticipacionMinHoras: j['anticipacion_min_horas'] as int? ?? 1,
        anticipacionMaxDias: j['anticipacion_max_dias'] as int? ?? 30,
        maxReservasMesInmueble: j['max_reservas_mes_inmueble'] as int?,
        horasLimiteCancelacion: j['horas_limite_cancelacion'] as int? ?? 24,
        requiereConfirmacion: j['requiere_confirmacion'] as bool? ?? true,
        horasLimiteConfirmacion: j['horas_limite_confirmacion'] as int? ?? 24,
        horasRecordatorio: j['horas_recordatorio'] as int? ?? 24,
        observaciones: j['observaciones'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'duracion_min_minutos': duracionMinMinutos,
        'duracion_max_minutos': duracionMaxMinutos,
        'anticipacion_min_horas': anticipacionMinHoras,
        'anticipacion_max_dias': anticipacionMaxDias,
        'max_reservas_mes_inmueble': maxReservasMesInmueble,
        'horas_limite_cancelacion': horasLimiteCancelacion,
        'requiere_confirmacion': requiereConfirmacion,
        'horas_limite_confirmacion': horasLimiteConfirmacion,
        'horas_recordatorio': horasRecordatorio,
        if (observaciones != null) 'observaciones': observaciones,
      };
}

class AmenidadModel {
  const AmenidadModel({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.capacidad,
    this.condicionesUso,
    this.activa = true,
    this.horarios = const [],
    this.reglas = const ReglaReservaModel(),
  });

  final int id;
  final String nombre;
  final String? descripcion;
  final int? capacidad;
  final String? condicionesUso;
  final bool activa;
  final List<AmenidadHorarioModel> horarios;
  final ReglaReservaModel reglas;

  factory AmenidadModel.fromJson(Map<String, dynamic> j) => AmenidadModel(
        id: j['id'] as int,
        nombre: j['nombre'] as String? ?? '',
        descripcion: j['descripcion'] as String?,
        capacidad: j['capacidad'] as int?,
        condicionesUso: j['condiciones_uso'] as String?,
        activa: j['activa'] as bool? ?? true,
        horarios: ((j['horarios'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AmenidadHorarioModel.fromJson)
            .toList(),
        reglas: j['reglas'] is Map<String, dynamic>
            ? ReglaReservaModel.fromJson(j['reglas'] as Map<String, dynamic>)
            : const ReglaReservaModel(),
      );
}

class ReservaModel {
  const ReservaModel({
    required this.id,
    required this.amenidad,
    required this.amenidadNombre,
    required this.usuario,
    required this.residente,
    this.inmueble,
    this.inmuebleCodigo,
    required this.fechaInicio,
    required this.fechaFin,
    this.numPersonas,
    required this.estado,
    required this.estadoNombre,
    this.observaciones,
    this.confirmadaEn,
    this.canceladaEn,
    this.motivoCancelacion,
    this.createdAt,
    this.puedeCancelar = false,
    this.cancelableHasta,
    this.venceConfirmacionEn,
  });

  final int id;
  final int amenidad;
  final String amenidadNombre;
  final int usuario;
  final String residente;
  final int? inmueble;
  final String? inmuebleCodigo;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int? numPersonas;
  final String estado;
  final String estadoNombre;
  final String? observaciones;
  final DateTime? confirmadaEn;
  final DateTime? canceladaEn;
  final String? motivoCancelacion;
  final DateTime? createdAt;
  final bool puedeCancelar;
  final DateTime? cancelableHasta;
  final DateTime? venceConfirmacionEn;

  factory ReservaModel.fromJson(Map<String, dynamic> j) => ReservaModel(
        id: j['id'] as int,
        amenidad: j['amenidad'] as int,
        amenidadNombre: j['amenidad_nombre'] as String? ?? '',
        usuario: j['usuario'] as int? ?? 0,
        residente: j['residente'] as String? ?? '',
        inmueble: j['inmueble'] as int?,
        inmuebleCodigo: j['inmueble_codigo'] as String?,
        fechaInicio: _dt(j['fecha_inicio']) ?? DateTime.now(),
        fechaFin: _dt(j['fecha_fin']) ?? DateTime.now(),
        numPersonas: j['num_personas'] as int?,
        estado: j['estado'] as String? ?? 'SOLICITADA',
        estadoNombre: j['estado_nombre'] as String? ?? (j['estado'] as String? ?? ''),
        observaciones: j['observaciones'] as String?,
        confirmadaEn: _dt(j['confirmada_en']),
        canceladaEn: _dt(j['cancelada_en']),
        motivoCancelacion: j['motivo_cancelacion'] as String?,
        createdAt: _dt(j['created_at']),
        puedeCancelar: j['puede_cancelar'] as bool? ?? false,
        cancelableHasta: _dt(j['cancelable_hasta']),
        venceConfirmacionEn: _dt(j['vence_confirmacion_en']),
      );
}

class ReservaHistorialModel {
  const ReservaHistorialModel({
    required this.id,
    required this.fecha,
    this.estadoAnterior,
    required this.estadoNuevo,
    required this.estadoNuevoNombre,
    this.usuarioNombre,
    this.detalle,
  });

  final int id;
  final DateTime fecha;
  final String? estadoAnterior;
  final String estadoNuevo;
  final String estadoNuevoNombre;
  final String? usuarioNombre;
  final String? detalle;

  factory ReservaHistorialModel.fromJson(Map<String, dynamic> j) => ReservaHistorialModel(
        id: j['id'] as int,
        fecha: _dt(j['fecha']) ?? DateTime.now(),
        estadoAnterior: j['estado_anterior'] as String?,
        estadoNuevo: j['estado_nuevo'] as String? ?? '',
        estadoNuevoNombre: j['estado_nuevo_nombre'] as String? ?? (j['estado_nuevo'] as String? ?? ''),
        usuarioNombre: j['usuario_nombre'] as String?,
        detalle: j['detalle'] as String?,
      );
}

class FranjaTiempoModel {
  const FranjaTiempoModel({
    required this.inicio,
    required this.fin,
    this.tipo,
    this.detalle,
  });

  final DateTime inicio;
  final DateTime fin;
  final String? tipo;
  final String? detalle;

  factory FranjaTiempoModel.fromJson(Map<String, dynamic> j) => FranjaTiempoModel(
        inicio: _dt(j['inicio']) ?? DateTime.now(),
        fin: _dt(j['fin']) ?? DateTime.now(),
        tipo: j['tipo'] as String?,
        detalle: j['detalle'] as String?,
      );
}

class DisponibilidadDiaModel {
  const DisponibilidadDiaModel({
    required this.amenidadId,
    required this.amenidad,
    required this.fecha,
    required this.activa,
    required this.abierta,
    this.capacidad,
    required this.duracionMinMinutos,
    required this.duracionMaxMinutos,
    this.horarios = const [],
    this.ocupados = const [],
    this.libres = const [],
  });

  final int amenidadId;
  final String amenidad;
  final String fecha;
  final bool activa;
  final bool abierta;
  final int? capacidad;
  final int duracionMinMinutos;
  final int duracionMaxMinutos;
  final List<Map<String, String>> horarios;
  final List<FranjaTiempoModel> ocupados;
  final List<FranjaTiempoModel> libres;

  factory DisponibilidadDiaModel.fromJson(Map<String, dynamic> j) => DisponibilidadDiaModel(
        amenidadId: j['amenidad_id'] as int? ?? 0,
        amenidad: j['amenidad'] as String? ?? '',
        fecha: j['fecha'] as String? ?? '',
        activa: j['activa'] as bool? ?? true,
        abierta: j['abierta'] as bool? ?? false,
        capacidad: j['capacidad'] as int?,
        duracionMinMinutos: j['duracion_min_minutos'] as int? ?? 30,
        duracionMaxMinutos: j['duracion_max_minutos'] as int? ?? 240,
        horarios: ((j['horarios'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((h) => {
                  'apertura': '${h['apertura'] ?? ''}',
                  'cierre': '${h['cierre'] ?? ''}',
                })
            .toList(),
        ocupados: ((j['ocupados'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FranjaTiempoModel.fromJson)
            .toList(),
        libres: ((j['libres'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FranjaTiempoModel.fromJson)
            .toList(),
      );
}

class EventoAgendaModel {
  const EventoAgendaModel({
    required this.tipo,
    required this.id,
    required this.amenidadId,
    required this.amenidad,
    required this.inicio,
    required this.fin,
    required this.titulo,
    this.estado,
    this.estadoNombre,
    this.residente,
    this.inmueble,
    this.numPersonas,
    this.mia = false,
    this.motivo,
  });

  final String tipo;
  final int id;
  final int amenidadId;
  final String amenidad;
  final DateTime inicio;
  final DateTime fin;
  final String titulo;
  final String? estado;
  final String? estadoNombre;
  final String? residente;
  final String? inmueble;
  final int? numPersonas;
  final bool mia;
  final String? motivo;

  factory EventoAgendaModel.fromJson(Map<String, dynamic> j) => EventoAgendaModel(
        tipo: j['tipo'] as String? ?? 'RESERVA',
        id: j['id'] as int? ?? 0,
        amenidadId: j['amenidad_id'] as int? ?? 0,
        amenidad: j['amenidad'] as String? ?? '',
        inicio: _dt(j['inicio']) ?? DateTime.now(),
        fin: _dt(j['fin']) ?? DateTime.now(),
        titulo: j['titulo'] as String? ?? '',
        estado: j['estado'] as String?,
        estadoNombre: j['estado_nombre'] as String?,
        residente: j['residente'] as String?,
        inmueble: j['inmueble'] as String?,
        numPersonas: j['num_personas'] as int?,
        mia: j['mia'] as bool? ?? false,
        motivo: j['motivo'] as String?,
      );
}

class OcupacionAmenidadModel {
  const OcupacionAmenidadModel({
    required this.amenidadId,
    required this.amenidad,
    this.capacidad,
    required this.horasDisponibles,
    required this.horasReservadas,
    this.ocupacionPct,
    required this.horasBloqueadas,
    required this.reservas,
    required this.tasaCancelacionPct,
    this.personasPromedio,
    this.usoAforoPromedioPct,
    this.horaPico,
  });

  final int amenidadId;
  final String amenidad;
  final int? capacidad;
  final double horasDisponibles;
  final double horasReservadas;
  final double? ocupacionPct;
  final double horasBloqueadas;
  final int reservas;
  final double tasaCancelacionPct;
  final double? personasPromedio;
  final double? usoAforoPromedioPct;
  final String? horaPico;

  factory OcupacionAmenidadModel.fromJson(Map<String, dynamic> j) => OcupacionAmenidadModel(
        amenidadId: j['amenidad_id'] as int? ?? 0,
        amenidad: j['amenidad'] as String? ?? '',
        capacidad: j['capacidad'] as int?,
        horasDisponibles: (j['horas_disponibles'] as num?)?.toDouble() ?? 0,
        horasReservadas: (j['horas_reservadas'] as num?)?.toDouble() ?? 0,
        ocupacionPct: (j['ocupacion_pct'] as num?)?.toDouble(),
        horasBloqueadas: (j['horas_bloqueadas'] as num?)?.toDouble() ?? 0,
        reservas: j['reservas'] as int? ?? 0,
        tasaCancelacionPct: (j['tasa_cancelacion_pct'] as num?)?.toDouble() ?? 0,
        personasPromedio: (j['personas_promedio'] as num?)?.toDouble(),
        usoAforoPromedioPct: (j['uso_aforo_promedio_pct'] as num?)?.toDouble(),
        horaPico: j['hora_pico'] as String?,
      );
}

class ReporteOcupacionModel {
  const ReporteOcupacionModel({
    required this.horasDisponibles,
    required this.horasReservadas,
    this.ocupacionPct,
    required this.reservas,
    required this.tasaCancelacionPct,
    required this.amenidades,
  });

  final double horasDisponibles;
  final double horasReservadas;
  final double? ocupacionPct;
  final int reservas;
  final double tasaCancelacionPct;
  final List<OcupacionAmenidadModel> amenidades;

  factory ReporteOcupacionModel.fromJson(Map<String, dynamic> j) {
    final res = (j['resumen'] as Map<String, dynamic>?) ?? const {};
    return ReporteOcupacionModel(
      horasDisponibles: (res['horas_disponibles'] as num?)?.toDouble() ?? 0,
      horasReservadas: (res['horas_reservadas'] as num?)?.toDouble() ?? 0,
      ocupacionPct: (res['ocupacion_pct'] as num?)?.toDouble(),
      reservas: res['reservas'] as int? ?? 0,
      tasaCancelacionPct: (res['tasa_cancelacion_pct'] as num?)?.toDouble() ?? 0,
      amenidades: ((j['amenidades'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OcupacionAmenidadModel.fromJson)
          .toList(),
    );
  }
}

