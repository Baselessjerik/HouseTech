# HouseTech - Plataforma SaaS de Gestión Residencial 🏢 Sostenible y Automatizada

**Housetech** es una solución web y móvil bajo el modelo Software como Servicio (SaaS) y arquitectura *multi-tenant*[cite: 10]. Diseñada para automatizar, centralizar y optimizar la administración operativa de conjuntos residenciales bajo la regulación del régimen de propiedad horizontal en Colombia (Ley 675 de 2001).

La plataforma elimina la fragmentación operativa provocada por canales informales (WhatsApp, llamadas, notas físicas y archivos Excel), garantizando la trazabilidad de la información, el control de acceso basado en roles y tiempos de respuesta inferiores a 2 segundos por transacción.

La arquitectura del proyecto está estructurada para mantener la cohesión y el desacoplamiento entre el cliente y el servidor[cite: 11, 12]:

```text
HouseTech/
├── backend/              # Proyecto Django REST Framework (API REST)
│   ├── manage.py
│   ├── requirements.txt  # Dependencias Python
│   └── ...               # Aplicaciones del backend (usuarios, pqrs, reservas)
├── frontend/             # Cliente web y móvil en Flutter
│   ├── lib/              # Código fuente Dart (UI, Riverpod/Providers, Servicios)
│   ├── pubspec.yaml      # Configuración de dependencias de Flutter
│   └── ...
└── README.md             # Documentación principal del proyecto

Guía de Instalación y Ejecución Local
Requisitos Previos
Flutter SDK (Versión 3.x o superior)

Python (Versión 3.10 o superior)

PostgreSQL (Servidor local o instancia en la nube habilitada)[cite: 11]

Navegador Web (Microsoft Edge o Google Chrome)

1. Clonar el Repositorio
    https://github.com/Baselessjerik/HouseTech
    cd HouseTech

2. Configurar y Ejecutar el Backend (Django)
    Ve al directorio del backend:
        cd backend

    Crea y activa un entorno virtual de Python
        python -m venv .venv
        # En Windows PowerShell:
        .\.venv\Scripts\Activate.ps1
        # En Linux/macOS:
        source .venv/bin/activate

    Instala las dependencias necesarias:
        pip install -r requirements.txt (Se encuentra en la carpeta Backend)
        
    Aplica las migraciones de la base de datos:
        python manage.py migrate (Aun no hay base de datos)

    Inicia el servidor de desarrollo:
        python manage.py runserver

3.Configurar y Ejecutar el Frontend (Flutter)
    Abre una nueva terminal en la raíz del proyecto y navega a la carpeta frontend:
        cd frontend
    
    Descarga los paquetes y dependencias de Dart:
        flutter pub get
    
    Verifica los dispositivos o navegadores disponibles:
        flutter devices
    
    Ejecuta la aplicación en Microsoft Edge (o Chrome):
        flutter run -d edge (Si usas Microsoft edge)
        flutter run -d chrome (Si usas Google chrome)

Comandos Útiles Durante la Ejecución en Flutter
    Cuando la aplicación de Flutter esté corriendo en la terminal:
        Presiona r para realizar un Hot Reload (actualiza la UI en subsegundos sin perder el estado).
        Presiona R para realizar un Hot Restart (reinicia el estado de la aplicación).
        Presiona q para detener el servidor de desarrollo.

Marco Legal y Normativo
    El desarrollo de la plataforma se rige bajo los lineamientos vigentes del marco legal colombiano:
        Ley 675 de 2001: Régimen de Propiedad Horizontal en Colombia[cite: 10, 11].
        Ley 1581 de 2012 (Habeas Data): Protección y tratamiento de datos personales de residentes[cite: 10, 11].
        Ley 1273 de 2009: Ley de Delitos Informáticos y control de acceso seguro a la información[cite: 10, 11].
