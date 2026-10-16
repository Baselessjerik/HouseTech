from django.urls import path

from .views import CambiarPasswordView, LoginView, LogoutView, MeView, RefreshView, RegistroView

app_name = "usuarios"

urlpatterns = [
    path("auth/login/", LoginView.as_view(), name="login"),
    path("auth/refresh/", RefreshView.as_view(), name="refresh"),
    path("auth/logout/", LogoutView.as_view(), name="logout"),
    path("auth/registro/", RegistroView.as_view(), name="registro"),
    path("auth/me/", MeView.as_view(), name="me"),
    path("auth/cambiar-password/", CambiarPasswordView.as_view(), name="cambiar-password"),
    # Próximos: auth/recuperar/, auth/restablecer/, usuarios/, roles/, permisos/
]
