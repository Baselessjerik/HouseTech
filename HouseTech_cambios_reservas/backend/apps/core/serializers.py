from rest_framework import serializers

from .models import Notificacion


class NotificacionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notificacion
        fields = ["id", "tipo", "titulo", "mensaje", "referencia_tipo", "referencia_id", "leida", "leida_en", "created_at"]
        read_only_fields = fields
