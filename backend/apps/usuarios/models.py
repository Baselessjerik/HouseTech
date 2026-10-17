"""Tablas del módulo Administración y Perfiles. Esquema real: core/sql/schema.sql."""
from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.db import models
from django.db.models import Q


class UsuarioManager(BaseUserManager):
    def get_by_natural_key(self, identificador):
        """Permite iniciar sesión con usuario O correo, sin distinguir mayúsculas."""
        usuario = self.filter(
            Q(username__iexact=identificador) | Q(email__iexact=identificador)
        ).first()
        if usuario is None:
            raise self.model.DoesNotExist
        return usuario

    def create_user(self, username, email, password, **extra):
        usuario = self.model(username=username, email=self.normalize_email(email), **extra)
        usuario.set_password(password)
        usuario.save(using=self._db)
        return usuario


class Rol(models.Model):
    codigo = models.CharField(max_length=40, unique=True)
    nombre = models.CharField(max_length=80)
    descripcion = models.TextField(null=True, blank=True)
    activo = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "roles"

    def __str__(self):
        return self.codigo


class Permiso(models.Model):
    codigo = models.CharField(max_length=80, unique=True)  # ej: pqr.gestionar
    modulo = models.CharField(max_length=40)
    descripcion = models.CharField(max_length=200)

    class Meta:
        managed = False
        db_table = "permisos"

    def __str__(self):
        return self.codigo


class RolPermiso(models.Model):
    pk = models.CompositePrimaryKey("rol_id", "permiso_id")
    rol = models.ForeignKey(Rol, on_delete=models.DO_NOTHING, related_name="rol_permisos")
    permiso = models.ForeignKey(Permiso, on_delete=models.DO_NOTHING, related_name="permiso_roles")

    class Meta:
        managed = False
        db_table = "roles_permisos"


class Usuario(AbstractBaseUser):
    class TipoDocumento(models.TextChoices):
        CC = "CC"
        CE = "CE"
        TI = "TI"
        PP = "PP"
        NIT = "NIT"

    tipo_documento = models.CharField(max_length=5, choices=TipoDocumento.choices, default=TipoDocumento.CC)
    numero_documento = models.CharField(max_length=30)
    nombres = models.CharField(max_length=100)
    apellidos = models.CharField(max_length=100)
    # unique=True solo satisface los chequeos de Django; la unicidad real (sin
    # distinguir mayúsculas) la imponen los índices lower() de la BD.
    username = models.CharField(max_length=60, unique=True)
    email = models.CharField(max_length=150)
    # Columnas con nombre distinto al que espera AbstractBaseUser:
    password = models.CharField(max_length=255, db_column="password_hash")
    last_login = models.DateTimeField(null=True, blank=True, db_column="ultimo_login")
    telefono = models.CharField(max_length=30, null=True, blank=True)
    activo = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = "username"
    REQUIRED_FIELDS = ["email", "nombres", "apellidos", "numero_documento"]

    objects = UsuarioManager()

    class Meta:
        managed = False
        db_table = "usuarios"

    def __str__(self):
        return self.username

    @property
    def is_active(self):
        return self.activo

    @property
    def nombre_completo(self):
        return f"{self.nombres} {self.apellidos}"

    def codigos_roles(self) -> list[str]:
        return list(
            Rol.objects.filter(activo=True, rol_usuarios__usuario_id=self.pk)
            .order_by("codigo")
            .values_list("codigo", flat=True)
        )

    def codigos_permisos(self) -> set[str]:
        """Permisos efectivos (unión de sus roles activos). Se cachea por instancia/petición."""
        if not hasattr(self, "_permisos_cache"):
            self._permisos_cache = set(
                RolPermiso.objects.filter(rol__activo=True, rol__rol_usuarios__usuario_id=self.pk)
                .values_list("permiso__codigo", flat=True)
            )
        return self._permisos_cache

    def tiene_permiso(self, codigo: str) -> bool:
        return codigo in self.codigos_permisos()


class UsuarioRol(models.Model):
    pk = models.CompositePrimaryKey("usuario_id", "rol_id")
    usuario = models.ForeignKey(Usuario, on_delete=models.DO_NOTHING, related_name="usuario_roles")
    rol = models.ForeignKey(Rol, on_delete=models.DO_NOTHING, related_name="rol_usuarios")
    asignado_por = models.ForeignKey(
        Usuario,
        null=True,
        blank=True,
        on_delete=models.DO_NOTHING,
        related_name="+",
        db_column="asignado_por",
    )
    asignado_en = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = "usuarios_roles"


class RecuperacionPassword(models.Model):
    usuario = models.ForeignKey(Usuario, on_delete=models.DO_NOTHING, related_name="recuperaciones")
    token_hash = models.CharField(max_length=255, unique=True)
    expira_en = models.DateTimeField()
    usado_en = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = "recuperacion_password"


class TokenRevocado(models.Model):
    """Lista negra de JWT (cierre de sesión seguro)."""

    jti = models.CharField(max_length=100, unique=True)
    usuario = models.ForeignKey(Usuario, null=True, on_delete=models.DO_NOTHING, related_name="+")
    expira_en = models.DateTimeField()
    revocado_en = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = "tokens_revocados"


class Dispositivo(models.Model):
    """Tokens FCM para notificaciones push desde Flutter."""

    class Plataforma(models.TextChoices):
        ANDROID = "ANDROID"
        IOS = "IOS"
        WEB = "WEB"

    usuario = models.ForeignKey(Usuario, on_delete=models.DO_NOTHING, related_name="dispositivos")
    token_push = models.CharField(max_length=255, unique=True)
    plataforma = models.CharField(max_length=10, choices=Plataforma.choices)
    activo = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "dispositivos"
