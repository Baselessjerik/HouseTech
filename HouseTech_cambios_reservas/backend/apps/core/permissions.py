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


def requiere_algun_permiso(*codigos: str):
    """Como `requiere_permiso`, pero basta con tener UNO de los permisos indicados."""

    class _RequiereAlguno(BasePermission):
        message = f"Se requiere alguno de los permisos: {', '.join(codigos)}."

        def has_permission(self, request, view):
            usuario = request.user
            return bool(
                usuario and usuario.is_authenticated and any(usuario.tiene_permiso(c) for c in codigos)
            )

    _RequiereAlguno.__name__ = f"RequiereAlguno[{'|'.join(codigos)}]"
    return _RequiereAlguno
