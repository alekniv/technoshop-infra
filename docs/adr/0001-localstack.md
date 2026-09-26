
# ADR-0001: Emular AWS con LocalStack en lugar de usar AWS real

Estado: Aceptado — 26/09/2026

## Contexto
No disponemos de capa gratuita de AWS (ya fue utilizada) y el presupuesto de nube
del laboratorio es $0. Aun así necesitamos practicar servicios de AWS (S3 para
backups, IAM, redes) y desplegarlos como código con Terraform.

## Alternativas evaluadas
1. AWS real con cuenta nueva: descartada, genera costos y riesgo de cargos inesperados.
2. Azure for Students: descartada, requiere ser estudiante y el diseño está pensado en AWS.
3. Simular sin API de AWS: descartada, no permite practicar Terraform ni IAM.
4. LocalStack Hobby: elegida, gratis para uso no comercial y compatible con la API de AWS.

## Decisión
Usamos LocalStack (plan Hobby, ~55 servicios de AWS) en un contenedor Docker dentro
de OPS01. La infraestructura se define con Terraform usando tflocal, y sirve como
entorno de pruebas antes de salir a una AWS real.

## Consecuencias
- Positivas: costo $0; el mismo código Terraform sirve para AWS real; se practica
  S3, IAM y redes sin riesgo.
- Negativas: EC2 no crea VMs reales (WEB01 se simula en VirtualBox); ENFORCE_IAM
  no está en Hobby, así que las políticas IAM no se hacen cumplir; S3 vive en OPS01,
  no es una copia fuera de la oficina de verdad; requiere cuenta y token.

  ## Servicios evaluados (plan Hobby)

| Servicio | ¿Incluido en Hobby? | Para qué lo usamos | Fuente |
|---|---|---|---|
| S3 | Sí (Hobby, Base, Ultimate). Persistencia soportada | Destino de backups con restic (versionado + Object Lock definidos en Terraform) | https://docs.localstack.cloud/aws/services/s3/ |
| IAM | Sí (Hobby, Base, Ultimate). Persistencia soportada. ⚠ El cumplimiento de políticas (ENFORCE_IAM) solo está en Base/Ultimate | Usuarios, roles y políticas de mínimo privilegio en Terraform; se validan con Checkov, no en tiempo de ejecución | https://docs.localstack.cloud/aws/services/iam/ · https://docs.localstack.cloud/aws/developer-tools/security-testing/iam-policy-enforcement/ |
| EC2 / VPC / Security Groups | Sí (Hobby, Base, Ultimate). Soporte y persistencia limitados | Solo red y reglas (VPC, subredes, Security Groups) con Terraform. La "instancia" real es WEB01 en VirtualBox | https://docs.localstack.cloud/aws/services/ec2/ |
| CloudWatch | Sí (Hobby, Base, Ultimate). Persistencia soportada | Opcional: práctica de métricas y alarmas vía Terraform. El monitoreo real lo hace Prometheus/Grafana en OPS01 | https://docs.localstack.cloud/aws/services/cloudwatch/ |

