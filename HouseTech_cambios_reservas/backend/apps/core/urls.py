from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import HealthView, NotificacionViewSet

app_name = "core"

router = SimpleRouter()
router.register("notificaciones", NotificacionViewSet, basename="notificacion")

urlpatterns = [
    path("health/", HealthView.as_view(), name="health"),
] + router.urls
