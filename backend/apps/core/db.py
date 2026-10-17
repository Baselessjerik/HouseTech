from django.db import connection


def set_audit_user(usuario_id) -> None:
    """Le dice a los triggers de auditoría qué usuario ejecuta la operación.

    Equivale a `SET LOCAL app.usuario_id = '<id>'` y solo vive hasta que termina
    la transacción actual. Por eso settings.DATABASES['default']['ATOMIC_REQUESTS']
    es True: sin transacción abierta el valor se pierde y `auditoria.usuario_id`
    quedaría en NULL. Fuera de una petición (shell, comandos) envuélvelo en
    `transaction.atomic()`.
    """
    with connection.cursor() as cursor:
        cursor.execute("SELECT set_config('app.usuario_id', %s, true)", [str(usuario_id)])
