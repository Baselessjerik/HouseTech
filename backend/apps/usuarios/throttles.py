from rest_framework.throttling import AnonRateThrottle


class SolicitarRecuperacionThrottle(AnonRateThrottle):
    scope = "recuperar"
    rate = "10/hour"


class RestablecerPasswordThrottle(AnonRateThrottle):
    """Frena la fuerza bruta sobre el código de 6 dígitos."""

    scope = "restablecer"
    rate = "10/hour"
