from rest_framework.permissions import BasePermission


def requiere_permiso(codigo: str):
    """Fábrica de permisos DRF basados en las tablas roles_permisos.

    Uso:  permission_classes = [IsAuthenticated, requiere_permiso("usuarios.gestionar")]
    """

    class _RequierePermiso(BasePermission):
        message = f"Se requiere el permiso '{codigo}'."

        def has_permission(self, request, view):
            usuario = request.user
            return bool(usuario and usuario.is_authenticated and usuario.tiene_permiso(codigo))

    _RequierePermiso.__name__ = f"RequierePermiso[{codigo}]"
    return _RequierePermiso
