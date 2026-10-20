import datetime as dt

from django.utils import timezone
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from apps.core.models import Copropiedad
from apps.inmuebles.models import Inmueble
from apps.usuarios.models import Usuario

from . import services
from .models import Amenidad, AmenidadHorario, BloqueoAmenidad, ReglaReserva, Reserva, ReservaHistorial


# --- amenidades: aforo, horarios y políticas de cancelación ---------------------------------
class AmenidadHorarioSerializer(serializers.ModelSerializer):
    class Meta:
        model = AmenidadHorario
        fields = ["dia_semana", "hora_apertura", "hora_cierre", "activo"]
        extra_kwargs = {"activo": {"default": True}}

    def validate_dia_semana(self, valor):
        if not 1 <= valor <= 7:
            raise serializers.ValidationError("Usa 1 (lunes) a 7 (domingo).")
        return valor

    def validate(self, attrs):
        if attrs["hora_cierre"] <= attrs["hora_apertura"]:
            raise serializers.ValidationError({"hora_cierre": "Debe ser posterior a la hora de apertura."})
        return attrs


class ReglaReservaSerializer(serializers.ModelSerializer):
    """Políticas de uso y de cancelación (`horas_limite_cancelacion`)."""

    class Meta:
        model = ReglaReserva
        fields = [
            "duracion_min_minutos", "duracion_max_minutos", "anticipacion_min_horas",
            "anticipacion_max_dias", "max_reservas_mes_inmueble", "horas_limite_cancelacion",
            "requiere_confirmacion", "horas_limite_confirmacion", "horas_recordatorio", "observaciones",
        ]
        extra_kwargs = {
            "horas_limite_confirmacion": {"min_value": 1},
            "horas_recordatorio": {"min_value": 0},
            "duracion_min_minutos": {"min_value": 1},
            "duracion_max_minutos": {"min_value": 1},
            "anticipacion_min_horas": {"min_value": 0},
            "anticipacion_max_dias": {"min_value": 1},
            "max_reservas_mes_inmueble": {"min_value": 1},
            "horas_limite_cancelacion": {"min_value": 0},
        }


class AmenidadSerializer(serializers.ModelSerializer):
    copropiedad = serializers.PrimaryKeyRelatedField(queryset=Copropiedad.objects.all(), required=False)
    capacidad = serializers.IntegerField(min_value=1, required=False, allow_null=True)
    horarios = AmenidadHorarioSerializer(many=True, required=False)
    reglas = ReglaReservaSerializer(required=False)
    estado_actual = serializers.SerializerMethodField()

    class Meta:
        model = Amenidad
        fields = [
            "id", "copropiedad", "nombre", "descripcion", "capacidad", "condiciones_uso", "activa",
            "horarios", "reglas", "estado_actual", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_estado_actual(self, obj):
        """DISPONIBLE / RESERVADA / BLOQUEADA / EN_MANTENIMIENTO. Solo en el detalle (1 consulta extra)."""
        if not self.context.get("incluir_estado"):
            return None
        return services.estado_actual_amenidad(obj.pk)

    def validate_nombre(self, valor):
        valor = valor.strip()
        copropiedad_id = (self.initial_data.get("copropiedad") if hasattr(self, "initial_data") else None) or (
            self.instance.copropiedad_id if self.instance else None
        )
        qs = Amenidad.objects.filter(nombre__iexact=valor)
        if copropiedad_id:
            qs = qs.filter(copropiedad_id=copropiedad_id)
        if self.instance:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError("Ya existe una amenidad con ese nombre.")
        return valor

    def validate_horarios(self, horarios):
        por_dia: dict[int, list] = {}
        for h in horarios:
            if h.get("activo", True):
                por_dia.setdefault(h["dia_semana"], []).append((h["hora_apertura"], h["hora_cierre"]))
        for dia, franjas in por_dia.items():
            franjas.sort()
            for (_, cierre), (apertura, _) in zip(franjas, franjas[1:]):
                if apertura < cierre:
                    raise serializers.ValidationError(f"Hay franjas que se solapan el día {dia}.")
        return horarios

    def validate(self, attrs):
        reglas = attrs.get("reglas")
        if reglas is not None:
            actual = services.obtener_regla(self.instance) if self.instance else ReglaReserva()
            minimo = reglas.get("duracion_min_minutos", actual.duracion_min_minutos)
            maximo = reglas.get("duracion_max_minutos", actual.duracion_max_minutos)
            if maximo < minimo:
                raise serializers.ValidationError({"reglas": "La duración máxima no puede ser menor que la mínima."})
        return attrs

    @staticmethod
    def _guardar_horarios(amenidad, horarios):
        amenidad.horarios.all().delete()
        AmenidadHorario.objects.bulk_create([AmenidadHorario(amenidad=amenidad, **h) for h in horarios])

    def create(self, validated_data):
        horarios = validated_data.pop("horarios", [])
        reglas = validated_data.pop("reglas", {})
        if "copropiedad" not in validated_data:
            validated_data["copropiedad"] = services.copropiedad_por_defecto()
        amenidad = Amenidad.objects.create(**validated_data)
        ReglaReserva.objects.create(amenidad=amenidad, **reglas)  # siempre existe una fila de reglas
        self._guardar_horarios(amenidad, horarios)
        return amenidad

    def update(self, instance, validated_data):
        horarios = validated_data.pop("horarios", None)
        reglas = validated_data.pop("reglas", None)
        for campo, valor in validated_data.items():
            setattr(instance, campo, valor)
        instance.save()
        if reglas is not None:
            regla, _ = ReglaReserva.objects.get_or_create(amenidad=instance)
            for campo, valor in reglas.items():
                setattr(regla, campo, valor)
            regla.save()
        if horarios is not None:  # reemplaza TODO el horario semanal
            self._guardar_horarios(instance, horarios)
        return Amenidad.objects.select_related("reglas").prefetch_related("horarios").get(pk=instance.pk)


# --- reservas ---------------------------------------------------------------------------------------
class ReservaSerializer(serializers.ModelSerializer):
    amenidad_nombre = serializers.CharField(source="amenidad.nombre", read_only=True)
    residente = serializers.CharField(source="usuario.nombre_completo", read_only=True)
    inmueble_codigo = serializers.CharField(source="inmueble.codigo_interno", read_only=True, default=None)
    estado = serializers.CharField(source="estado.codigo", read_only=True)
    estado_nombre = serializers.CharField(source="estado.nombre", read_only=True)
    puede_cancelar = serializers.SerializerMethodField()
    cancelable_hasta = serializers.SerializerMethodField()
    vence_confirmacion_en = serializers.SerializerMethodField()

    class Meta:
        model = Reserva
        fields = [
            "id", "amenidad", "amenidad_nombre", "usuario", "residente", "inmueble", "inmueble_codigo",
            "fecha_inicio", "fecha_fin", "num_personas", "estado", "estado_nombre", "observaciones",
            "confirmada_en", "cancelada_en", "motivo_cancelacion", "created_at",
            "puede_cancelar", "cancelable_hasta", "vence_confirmacion_en",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.BooleanField())
    def get_puede_cancelar(self, obj):
        return services.puede_cancelar(obj, self.context["request"].user)

    @extend_schema_field(serializers.DateTimeField(allow_null=True))
    def get_cancelable_hasta(self, obj):
        return services.limite_cancelacion(obj) if not obj.estado.es_final else None


    @extend_schema_field(serializers.DateTimeField(allow_null=True))
    def get_vence_confirmacion_en(self, obj):
        """Solo mientras está SOLICITADA: cuándo se libera si nadie la confirma."""
        return services.limite_confirmacion(obj) if obj.estado.codigo == "SOLICITADA" else None


class ReservaCrearSerializer(serializers.Serializer):
    amenidad = serializers.PrimaryKeyRelatedField(queryset=Amenidad.objects.all())
    fecha_inicio = serializers.DateTimeField()
    fecha_fin = serializers.DateTimeField()
    num_personas = serializers.IntegerField(min_value=1)
    inmueble = serializers.PrimaryKeyRelatedField(queryset=Inmueble.objects.filter(activo=True), required=False, allow_null=True)
    usuario = serializers.PrimaryKeyRelatedField(
        queryset=Usuario.objects.filter(activo=True), required=False,
        help_text="Solo administradores: reservar en nombre de otro usuario.",
    )
    observaciones = serializers.CharField(required=False, allow_blank=True, allow_null=True, max_length=1000)

    def validate(self, attrs):
        if attrs["fecha_fin"] <= attrs["fecha_inicio"]:
            raise serializers.ValidationError({"fecha_fin": "Debe ser posterior a la fecha de inicio."})
        solicitante = self.context["request"].user
        if "usuario" in attrs and attrs["usuario"].pk != solicitante.pk and not services.es_gestor(solicitante):
            raise serializers.ValidationError({"usuario": "Solo la administración puede reservar a nombre de otro usuario."})
        return attrs


class MotivoSerializer(serializers.Serializer):
    motivo = serializers.CharField(required=False, allow_blank=True, max_length=500)


class ReservaHistorialSerializer(serializers.ModelSerializer):
    """RF11: cada cambio de estado de una reserva, quién lo hizo y cuándo."""

    estado_anterior = serializers.CharField(source="estado_anterior.codigo", read_only=True, default=None)
    estado_nuevo = serializers.CharField(source="estado_nuevo.codigo", read_only=True)
    estado_nuevo_nombre = serializers.CharField(source="estado_nuevo.nombre", read_only=True)
    usuario_nombre = serializers.CharField(source="usuario.nombre_completo", read_only=True, default=None)

    class Meta:
        model = ReservaHistorial
        fields = ["id", "fecha", "estado_anterior", "estado_nuevo", "estado_nuevo_nombre", "usuario", "usuario_nombre", "detalle"]
        read_only_fields = fields


# --- bloqueos ------------------------------------------------------------------------------------------
class BloqueoSerializer(serializers.ModelSerializer):
    amenidad_nombre = serializers.CharField(source="amenidad.nombre", read_only=True)
    cancelar_reservas = serializers.BooleanField(write_only=True, required=False, default=False)

    class Meta:
        model = BloqueoAmenidad
        fields = [
            "id", "amenidad", "amenidad_nombre", "fecha_inicio", "fecha_fin", "motivo",
            "cancelado", "cancelado_en", "creado_por", "created_at", "cancelar_reservas",
        ]
        read_only_fields = ["id", "cancelado", "cancelado_en", "creado_por", "created_at"]

    def validate(self, attrs):
        if attrs["fecha_fin"] <= attrs["fecha_inicio"]:
            raise serializers.ValidationError({"fecha_fin": "Debe ser posterior a la fecha de inicio."})
        return attrs


# --- parámetros de consulta (agenda, disponibilidad, reportes) --------------------------------------------
def _lista_enteros(texto, campo):
    try:
        return [int(x) for x in texto.split(",") if x.strip()]
    except ValueError:
        raise serializers.ValidationError({campo: "Usa ids numéricos separados por coma."})


class DisponibilidadQuerySerializer(serializers.Serializer):
    fecha = serializers.DateField(required=False, help_text="Por defecto, hoy.")


class VerificarQuerySerializer(serializers.Serializer):
    inicio = serializers.DateTimeField()
    fin = serializers.DateTimeField()
    num_personas = serializers.IntegerField(min_value=1, required=False)
    inmueble = serializers.IntegerField(required=False)


class AgendaQuerySerializer(serializers.Serializer):
    desde = serializers.DateField(required=False, help_text="Por defecto, hoy.")
    hasta = serializers.DateField(required=False, help_text="Inclusive. Por defecto, desde + 30 días. Máximo 92 días.")
    amenidad = serializers.CharField(required=False, help_text="Ids separados por coma.")
    estado = serializers.CharField(required=False, help_text="Códigos separados por coma.")

    def validate(self, attrs):
        hoy = timezone.localdate()
        desde = attrs.get("desde") or hoy
        hasta = attrs.get("hasta") or desde + dt.timedelta(days=30)
        if hasta < desde:
            raise serializers.ValidationError({"hasta": "No puede ser anterior a 'desde'."})
        if (hasta - desde).days > 92:
            raise serializers.ValidationError({"hasta": "El rango máximo es de 92 días."})
        estados = [e.strip().upper() for e in attrs.get("estado", "").split(",") if e.strip()]
        invalidos = set(estados) - set(services.ESTADOS_RESERVA)
        if invalidos:
            raise serializers.ValidationError({"estado": f"Estados desconocidos: {', '.join(sorted(invalidos))}."})
        return {
            "desde": desde, "hasta": hasta, "estados": estados or None,
            "amenidades": _lista_enteros(attrs.get("amenidad", ""), "amenidad"),
        }


class ReporteFiltrosSerializer(serializers.Serializer):
    desde = serializers.DateField(required=False, help_text="Por defecto, hace 29 días.")
    hasta = serializers.DateField(required=False, help_text="Inclusive. Por defecto, hoy. Rango máximo: 366 días.")
    amenidad = serializers.CharField(required=False, help_text="Ids separados por coma.")
    estado = serializers.CharField(required=False, help_text="Estados que cuentan como ocupación. Por defecto CONFIRMADA,FINALIZADA.")
    inmueble = serializers.IntegerField(required=False)
    usuario = serializers.IntegerField(required=False)
    agrupar = serializers.ChoiceField(choices=["dia", "semana", "mes"], default="dia")
    incluir_inactivas = serializers.BooleanField(default=False)
    formato = serializers.ChoiceField(choices=["json", "csv"], default="json")

    def validate(self, attrs):
        hasta = attrs.get("hasta") or timezone.localdate()
        desde = attrs.get("desde") or hasta - dt.timedelta(days=29)
        if hasta < desde:
            raise serializers.ValidationError({"hasta": "No puede ser anterior a 'desde'."})
        if (hasta - desde).days > 366:
            raise serializers.ValidationError({"hasta": "El rango máximo es de 366 días."})
        estados = [e.strip().upper() for e in attrs.get("estado", "").split(",") if e.strip()]
        invalidos = set(estados) - set(services.ESTADOS_RESERVA)
        if invalidos:
            raise serializers.ValidationError({"estado": f"Estados desconocidos: {', '.join(sorted(invalidos))}."})
        return {
            "desde": desde, "hasta": hasta, "estados": estados,
            "amenidades": _lista_enteros(attrs.get("amenidad", ""), "amenidad"),
            "inmueble": attrs.get("inmueble"), "usuario": attrs.get("usuario"),
            "agrupar": attrs["agrupar"], "incluir_inactivas": attrs["incluir_inactivas"], "formato": attrs["formato"],
        }
