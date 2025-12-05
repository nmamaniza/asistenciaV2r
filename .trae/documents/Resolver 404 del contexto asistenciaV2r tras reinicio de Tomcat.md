## Objetivo
- Diagnosticar y corregir el 404 en la raíz del contexto `asistenciaV2r` tras reiniciar Tomcat.

## Verificaciones de despliegue
- Confirmar que el contexto está desplegado:
  - Que existe `/opt/tomcat/webapps/asistenciaV2r/` con archivos estáticos (`index.html`, `dashboard_admin.html`).
  - Que no hay conflicto simultáneo entre `asistenciaV2r.war` y el directorio expandido `asistenciaV2r/` (usar solo uno).
- Revisar logs de Tomcat (solo lectura):
  - `catalina.out`, `localhost.<date>.log` para errores de despliegue del contexto.
  - Buscar excepciones de `web.xml` o de filtros/servlets.

## Configuración de bienvenida y estáticos
- Validar `WEB-INF/web.xml` tiene `welcome-file-list` con `index.html` y está bien formado.
- Confirmar que `index.html` existe en la raíz del contexto y es accesible con URL directa (`/asistenciaV2r/index.html`).
- Asegurar que ningún `<servlet-mapping>` o filtro captura `/*` y bloquea el default servlet de Tomcat para estáticos.

## Filtros y seguridad
- Revisar `SessionPersistenceFilter` mapeado a `/*`:
  - Verificar que siempre llama `chain.doFilter(request, response)` y no emite 404.
  - Asegurar que no intercepta recursos estáticos (se puede filtrar por contenido-type o path prefix). 
- Confirmar que Spring Security no bloquea acceso anónimo a recursos HTML/CSS/JS del contexto.

## Corrección de despliegue
- Si hay conflicto WAR+directorio:
  - Elegir despliegue por WAR:
    - `mvn clean package` (ya generamos `target/asistenciaV2r.war`).
    - Copiar WAR a `webapps/`, remover (o renombrar) el directorio expandido si existe para evitar conflictos.
    - Reiniciar Tomcat.
- Si `web.xml` o filtro tienen error:
  - Ajustar mapeos (quitar captura de `/*` en servlets que no sean default; mantener filtros pero delegando).

## Pruebas de humo
- Acceder:
  - `/asistenciaV2r/` (debería resolver a `index.html` por welcome-file).
  - `/asistenciaV2r/index.html` (directo).
  - Páginas admin con submenú unificado:
    - `/asistenciaV2r/dashboard_admin.html`
    - `/asistenciaV2r/biometric_sync.html`
    - `/asistenciaV2r/procesados.html`
    - `/asistenciaV2r/permisos.html`
    - `/asistenciaV2r/consolidado.html`
    - `/asistenciaV2r/perfil.html`
- Validar que no hay 404 y el submenú navega correctamente.

## Entregables
- Estado del despliegue corregido (WAR o directorio único).
- Confirmación de acceso a raíz y páginas.
- Ajustes mínimos en filtros/mapeos si corresponde.

## Confirmación
- Tras tu aprobación, ejecuto las verificaciones, realizo la corrección seleccionada (WAR único + reinicio) y valido el acceso a todas las páginas.