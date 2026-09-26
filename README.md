# technoshop-infra

Repositorio de infraestructura de TechnoShop SRL, una PyME de e-commerce (laboratorio).
Contiene todo lo necesario para construir, configurar y operar sus servidores: código de infraestructura, automatizaciones y documentación.

## Estructura

- `docs/` – Documentación general de la infraestructura (red, servidores, inventario).
- `docs/adr/` – Registros de decisiones de arquitectura (ADR): qué se decidió y por qué.
- `docs/runbooks/` – Procedimientos paso a paso para tareas operativas y resolución de incidentes.
- `terraform/` – Infraestructura como código para el despliegue de servicios de AWS en LocalStack.
- `ansible/` – Configuraciones automatizadas para los servidores de la infraestructura.
- `scripts/` – Scripts en Powershell y Bash para automatizar tareas operativas (ej: backups, administración de usuarios, etc).

## Reglas del repo

- No se suben secretos (contraseñas, tokens, claves). Se guardan en el gestor de contraseñas.
- Todo cambio entra por Pull Request; no se hacen cambios directos en `main`.
- Cada decisión técnica importante se documenta como ADR en `docs/adr/`.
