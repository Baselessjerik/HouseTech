import re

from django.utils import timezone
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from apps.usuarios.models import Rol, Usuario

from . import services
from .models import (
    AmenidadRef,
    Bloqueo,
    CategoriaComunicado,
    Comunicado,
    ComunicadoHistorial,
    Mantenimiento,
    Notificacion,
)

COLOR_HEX = re.compile(r"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")


def _nombre(usuario):
    return usuario.nombre_completo if usuario else None


# ------------------------------------------------------------------------- mantenimientos
class MantenimientoSerializer(serializers.ModelSerializer):
    amenidad_nombre = serializers.CharField(source="amenidad.nombre", read_only=True, default=None)
    estado = serializers.CharField(source="estado.codigo", read_only=True)
    estado_nombre = serializers.CharField(source="estado.nombre", read_only=True)
    creado_por_nombre = serializers.SerializerMethodField()
    bloqueos_activos = serializers.SerializerMethodField()

    class Meta:
        model = Mantenimiento
        fields = [
            "id", "amenidad", "amenidad_nombre", "titulo", "descripcion", "fecha_inicio", "fecha_fin",
            "estado", "estado_nombre", "responsable", "creado_por", "creado_por_nombre",
            "bloqueos_activos", "created_at", "updated_at",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_creado_por_nombre(self, obj):
        return _nombre(obj.creado_por)

    @extend_schema_field(serializers.IntegerField())
    def get_bloqueos_activos(self, obj):
        return obj.bloqueos.filter(cancelado=False, fecha_fin__gt=timezone.now()).count()


class MantenimientoEscrituraSerializer(serializers.Serializer):
    amenidad = serializers.PrimaryKeyRelatedField(
        queryset=AmenidadRef.objects.filter(activa=True), required=False, allow_null=True
    )
    titulo = serializers.CharField(max_length=150)
    descripcion = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    fecha_inicio = serializers.DateTimeField()
    fecha_fin = serializers.DateTimeField()
    responsable = serializers.CharField(max_length=150, required=False, allow_blank=True, allow_null=True)
    crear_bloqueo = serializers.BooleanField(required=False, default=False, write_only=True)

    def validate(self, attrs):
        inicio = attrs.get("fecha_inicio", getattr(self.instance, "fecha_inicio", None))
        fin = attrs.get("fecha_fin", getattr(self.instance, "fecha_fin", None))
        if inicio and fin and fin <= inicio:
            raise serializers.ValidationError({"fecha_fin": "La fecha de fin debe ser posterior a la de inicio."})
        return attrs


# ----------------------------------------------------------------------------- bloqueos
class BloqueoSerializer(serializers.ModelSerializer):
    amenidad_nombre = serializers.CharField(source="amenidad.nombre", read_only=True)
    mantenimiento_titulo = serializers.CharField(source="mantenimiento.titulo", read_only=True, default=None)
    estado = serializers.SerializerMethodField()
    creado_por_nombre = serializers.SerializerMethodField()

    class Meta:
        model = Bloqueo
        fields = [
            "id", "amenidad", "amenidad_nombre", "mantenimiento", "mantenimiento_titulo", "fecha_inicio",
            "fecha_fin", "motivo", "cancelado", "cancelado_en", "estado", "creado_por", "creado_por_nombre",
            "created_at", "updated_at",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.ChoiceField(choices=["PROGRAMADO", "ACTIVO", "FINALIZADO", "CANCELADO"]))
    def get_estado(self, obj):
        return services.estado_bloqueo(obj)

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_creado_por_nombre(self, obj):
        return _nombre(obj.creado_por)


class BloqueoEscrituraSerializer(serializers.Serializer):
    amenidad = serializers.PrimaryKeyRelatedField(queryset=AmenidadRef.objects.filter(activa=True), required=False)
    mantenimiento = serializers.PrimaryKeyRelatedField(
        queryset=Mantenimiento.objects.all(), required=False, allow_null=True
    )
    fecha_inicio = serializers.DateTimeField()
    fecha_fin = serializers.DateTimeField()
    motivo = serializers.CharField(min_length=3, max_length=500)

    def validate(self, attrs):
        if self.instance is None and "amenidad" not in attrs:
            raise serializers.ValidationError({"amenidad": "Este campo es requerido."})
        if self.instance is not None and "amenidad" in attrs and attrs["amenidad"].pk != self.instance.amenidad_id:
            raise serializers.ValidationError(
                {"amenidad": "No se puede cambiar la amenidad: cancela el bloqueo y crea otro."}
            )
        inicio = attrs.get("fecha_inicio", getattr(self.instance, "fecha_inicio", None))
        fin = attrs.get("fecha_fin", getattr(self.instance, "fecha_fin", None))
        if inicio and fin and fin <= inicio:
            raise serializers.ValidationError({"fecha_fin": "La fecha de fin debe ser posterior a la de inicio."})
        mant = attrs.get("mantenimiento")
        amenidad_id = attrs["amenidad"].pk if "amenidad" in attrs else getattr(self.instance, "amenidad_id", None)
        if mant is not None and mant.amenidad_id not in (None, amenidad_id):
            raise serializers.ValidationError({"mantenimiento": "El mantenimiento pertenece a otra amenidad."})
        return attrs


class CancelarBloqueoSerializer(serializers.Serializer):
    motivo = serializers.CharField(required=False, allow_blank=True, max_length=500)


# --------------------------------------------------------------------------- disponibilidad
class _BloqueoResumenSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    fecha_inicio = serializers.DateTimeField()
    fecha_fin = serializers.DateTimeField()
    motivo = serializers.CharField(allow_null=True)


class DisponibilidadSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    nombre = serializers.CharField()
    descripcion = serializers.CharField(allow_null=True)
    capacidad = serializers.IntegerField(allow_null=True)
    estado = serializers.ChoiceField(choices=["DISPONIBLE", "RESERVADA", "BLOQUEADA", "EN_MANTENIMIENTO"])
    motivo = serializers.CharField(allow_null=True)
    desde = serializers.DateTimeField(allow_null=True)
    hasta = serializers.DateTimeField(allow_null=True)
    proximo_bloqueo = _BloqueoResumenSerializer(allow_null=True)
    proximo_mantenimiento = _BloqueoResumenSerializer(allow_null=True)


# ----------------------------------------------------------------------------- categorías
class CategoriaSerializer(serializers.ModelSerializer):
    class Meta:
        model = CategoriaComunicado
        fields = ["id", "nombre", "descripcion", "color", "activa"]
        read_only_fields = ["id"]

    def validate_nombre(self, valor):
        valor = valor.strip()
        qs = CategoriaComunicado.objects.filter(nombre__iexact=valor)
        if self.instance is not None:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError("Ya existe una categoría con ese nombre.")
        return valor

    def validate_color(self, valor):
        if valor and not COLOR_HEX.match(valor):
            raise serializers.ValidationError("El color debe tener formato hexadecimal, por ejemplo #1E88E5.")
        return valor


# ----------------------------------------------------------------------------- comunicados
class ComunicadoSerializer(serializers.ModelSerializer):
    categoria_nombre = serializers.CharField(source="categoria.nombre", read_only=True, default=None)
    categoria_color = serializers.CharField(source="categoria.color", read_only=True, default=None)
    autor_nombre = serializers.SerializerMethodField()
    rol_destino_codigo = serializers.CharField(source="rol_destino.codigo", read_only=True, default=None)
    destinatarios = serializers.SerializerMethodField()

    class Meta:
        model = Comunicado
        fields = [
            "id", "categoria", "categoria_nombre", "categoria_color", "titulo", "contenido", "autor",
            "autor_nombre", "estado", "audiencia", "rol_destino", "rol_destino_codigo", "destinatarios",
            "fecha_programada", "fecha_publicacion", "fecha_expiracion", "created_at", "updated_at",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_autor_nombre(self, obj):
        return _nombre(obj.autor)

    @extend_schema_field(serializers.ListField(child=serializers.IntegerField()))
    def get_destinatarios(self, obj):
        return services.ids_destinatarios(obj) if obj.audiencia == Comunicado.Audiencia.USUARIOS else []


class AvisoSerializer(serializers.ModelSerializer):
    """Vista del residente (RF14): solo lo necesario para leer el aviso."""

    categoria_nombre = serializers.CharField(source="categoria.nombre", read_only=True, default=None)
    categoria_color = serializers.CharField(source="categoria.color", read_only=True, default=None)
    autor_nombre = serializers.SerializerMethodField()

    class Meta:
        model = Comunicado
        fields = [
            "id", "categoria", "categoria_nombre", "categoria_color", "titulo", "contenido", "autor_nombre",
            "fecha_publicacion", "fecha_expiracion",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_autor_nombre(self, obj):
        return _nombre(obj.autor)


class ComunicadoEscrituraSerializer(serializers.Serializer):
    categoria = serializers.PrimaryKeyRelatedField(
        queryset=CategoriaComunicado.objects.filter(activa=True), required=False, allow_null=True
    )
    titulo = serializers.CharField(max_length=200)
    contenido = serializers.CharField()
    audiencia = serializers.ChoiceField(choices=Comunicado.Audiencia.choices, required=False)
    rol_destino = serializers.PrimaryKeyRelatedField(
        queryset=Rol.objects.filter(activo=True), required=False, allow_null=True
    )
    destinatarios = serializers.ListField(child=serializers.IntegerField(), required=False, write_only=True)
    fecha_expiracion = serializers.DateTimeField(required=False, allow_null=True)

    def validate_fecha_expiracion(self, valor):
        if valor is not None and valor <= timezone.now():
            raise serializers.ValidationError("La fecha de expiración debe ser futura.")
        return valor

    def validate(self, attrs):
        inst = self.instance
        audiencia = attrs.get("audiencia", inst.audiencia if inst else Comunicado.Audiencia.TODOS)
        if audiencia == Comunicado.Audiencia.ROL:
            rol = attrs.get("rol_destino", inst.rol_destino if inst else None)
            if rol is None:
                raise serializers.ValidationError({"rol_destino": "Selecciona el rol destinatario."})
        if audiencia == Comunicado.Audiencia.USUARIOS:
            ids = attrs.get("destinatarios")
            if ids is None and inst is not None:
                ids = services.ids_destinatarios(inst)
            if not ids:
                raise serializers.ValidationError({"destinatarios": "Selecciona al menos un destinatario."})
            ids = set(ids)
            if Usuario.objects.filter(pk__in=ids, activo=True).count() != len(ids):
                raise serializers.ValidationError({"destinatarios": "Hay usuarios inexistentes o inactivos."})
        if "audiencia" not in attrs and inst is None:
            attrs["audiencia"] = audiencia
        expira = attrs.get("fecha_expiracion", inst.fecha_expiracion if inst else None)
        programada = inst.fecha_programada if inst and inst.estado == Comunicado.Estado.PROGRAMADO else None
        if expira and programada and expira <= programada:
            raise serializers.ValidationError(
                {"fecha_expiracion": "La expiración debe ser posterior a la fecha programada."}
            )
        return attrs


class ProgramarSerializer(serializers.Serializer):
    fecha_programada = serializers.DateTimeField()


class ComunicadoHistorialSerializer(serializers.ModelSerializer):
    usuario_nombre = serializers.SerializerMethodField()

    class Meta:
        model = ComunicadoHistorial
        fields = [
            "id", "comunicado", "usuario", "usuario_nombre", "estado_anterior", "titulo_anterior",
            "contenido_anterior", "fecha",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_usuario_nombre(self, obj):
        return _nombre(obj.usuario)


# -------------------------------------------------------------------------- notificaciones
class NotificacionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notificacion
        fields = [
            "id", "tipo", "titulo", "mensaje", "referencia_tipo", "referencia_id", "canal", "leida",
            "leida_en", "created_at",
        ]
        read_only_fields = fields


# ------------------------------------------------------------------------------ opciones
class OpcionRolSerializer(serializers.ModelSerializer):
    class Meta:
        model = Rol
        fields = ["id", "codigo", "nombre"]


class OpcionUsuarioSerializer(serializers.ModelSerializer):
    nombre = serializers.CharField(source="nombre_completo", read_only=True)

    class Meta:
        model = Usuario
        fields = ["id", "username", "nombre", "email"]
