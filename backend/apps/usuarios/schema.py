from drf_spectacular.extensions import OpenApiAuthenticationExtension


class HouseTechJWTScheme(OpenApiAuthenticationExtension):
    """Habilita el botón 'Authorize' (Bearer) en /api/docs/."""

    target_class = "apps.usuarios.authentication.HouseTechJWTAuthentication"
    name = "bearerAuth"

    def get_security_definition(self, auto_schema):
        return {"type": "http", "scheme": "bearer", "bearerFormat": "JWT"}
