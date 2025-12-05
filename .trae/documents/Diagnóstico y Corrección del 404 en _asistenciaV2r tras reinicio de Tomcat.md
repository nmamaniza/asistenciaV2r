## Objetivo
- Identificar por qué `/asistenciaV2r/` devuelve 404 y corregir el despliegue para que la raíz sirva `index.html` y el resto de páginas admin.

## Verificaciones (solo lectura)
- Confirmar despliegue del contexto:
  - Validar que existe el directorio `webapps/asistenciaV2r/` con `index.html` y páginas admin.
  - Comprobar si coexisten `asistenciaV2r.war` y el directorio `asistenciaV2r/` (esto suele causar conflictos). 
- Revisar logs de Tomcat:
  - `catalina.out` y `localhost.*.log` para errores de despliegue del contexto o problemas con `web.xml`.
- Comprobar configuración de bienvenida y estáticos:
  - `WEB-INF/web.xml` tiene `welcome-file-list` con `index.html` y no hay `servlet-mapping` que capture `/*`.
  - Validar filtro `SessionPersistenceFilter` mapeado a `/*` no interrumpe entrega de HTML/CSS/JS (debe delegar con `chain.doFilter`).

## Corrección (despliegue)
- Elegir despliegue por WAR único para evitar conflictos:
  - Generar WAR (`mvn -q clean package`) ya disponible en `target/asistenciaV2r.war`.
  - Eliminar/renombrar el directorio expandido `webapps/asistenciaV2r/` si existe.
  - Copiar `asistenciaV2r.war` a `webapps/`.
  - Reiniciar Tomcat.
- Alternativa si se mantiene el directorio expandido:
  - Asegurar que NO existe el WAR simultáneamente.
  - Verificar permisos de lectura sobre `index.html` y páginas.

## Pruebas de humo
- Acceder a:
  - `/asistenciaV2r/` (debe resolver a `index.html`).
  - `/asistenciaV2r/index.html` y páginas admin: `dashboard_admin.html`, `biometric_sync.html`, `procesados.html`, `permisos.html`, `consolidado.html`, `perfil.html`.
- Validar navegación con rutas absolutas `/asistenciaV2r/...` y estado 200.

## Entregables
- Contexto `asistenciaV2r` desplegado correctamente.
- Acceso a raíz y páginas admin sin 404.
- Notas sobre cualquier ajuste requerido en filtros (`SessionPersistenceFilter`) si impedían recursos estáticos.

## Confirmación
- Tras tu confirmación, ejecuto las verificaciones, realizo el despliegue por WAR único y reinicio, luego valido que el 404 desaparece y que todas las páginas están accesibles.