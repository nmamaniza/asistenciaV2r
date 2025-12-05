**Resumen**

* Unificar navegación con un submenú consistente en todas las vistas admin.

* Completar Procesados con ejecución del script y grilla editable en OpenUI5 (ya adelantado).

* Implementar lógica de Permisos (LSG y Lactancia) respaldada por las tablas del script SQL.

* Crear Consolidado mensual mostrando el campo `final` por usuario y día.

* Implementar Perfiles para alta/edición de usuarios vía OpenUI5.

**Navegación/Submenú**

* Añadir el mismo dropdown de acceso rápido usado en `dashboard_admin.html` en todas las páginas:

  * Archivos a ajustar: `biometric_sync.html` (no lo tiene aún), revisar `procesados.html`, `permisos.html`, `consolidado.html`, `perfil.html` para unificar estilos y el cargado de `userInfo`.

  * Endpoint de usuario ya disponible: `UserInfoServlet` en `src/main/java/com/asistenciav2/servlet/UserInfoServlet.java:20`.

**Sincronización**

* Mantener la vista en `biometric_sync.html` y añadir el submenú.

* Backend ya operativo para sincronización en tiempo real:

  * Arranque/estado/stream: `BiometricSyncServlet` en `src/main/java/com/asistenciav2/servlet/BiometricSyncServlet.java:29` con acciones `startScript`, `status`, `stream`.

* UI: conservar la tabla de últimos registros y el panel de salida en vivo.

**Procesados**

* La página `procesados.html` ya implementa:

  * Form de parámetros (`fechaInicio`, `fechaFin`, `dni`) y botón Procesar.

  * Grilla OpenUI5 con columnas: `id, dni, modalidad, cargo, área, nombre, fecha, obs, doc, final, horaint` y edición inline de `doc` y `final`.

  * Filtros por año, mes y búsqueda (`q`) por DNI o nombre.

* Backend ya disponible y referenciado:

  * Lanzar script: `ProcessAttendanceServlet` `/api/process-attendance` en `src/main/java/com/asistenciav2/servlet/ProcessAttendanceServlet.java:18` (mapea `fechaInicio/fechaFin/dni` a `--fecha-inicio/--fecha-fin/--dni`).

  * Datos procesados: `ProcessedDataServlet` `/api/processed-data` en `src/main/java/com/asistenciav2/servlet/ProcessedDataServlet.java:11`.

  * Actualización `doc` y `final`: `UpdateDailyAttendanceServlet` `/api/processed-update` en `src/main/java/com/asistenciav2/servlet/UpdateDailyAttendanceServlet.java:10`.

* Mejora prevista: añadir visualización de salida del proceso vía SSE (`action=stream`) como en sincronización, en la parte superior de `procesados.html`.

**Permisos (LSG y Lactancia)**

* Referencia de modelo en `asistenciaV3vc_mejorado.sql` (tablas `users`, `jobassignments`, `permissiontypes`, `permissions` y programación de lactancia; vistas como `vw_permisos_activos`).

* Implementar endpoints:

  * `GET /api/permission-types`: listar tipos (`LSG`, `LACTANCIA`) y sus atributos (doble cargo, minutos diarios, etc.).

  * `GET /api/permissions?userId=...&estado=...`: listar permisos del usuario y permisos activos (opcionalmente usando `vw_permisos_activos`).

  * `POST /api/permissions`: crear permiso. Campos:

    * `userId`, `permissionType` (`LSG`|`LACTANCIA`), `fechaini`, `fechafin`, `jobassignmentId` (opcional), `minutosDiarios`/`diasMaximo` para lactancia.

  * `GET/POST /api/lactancia-schedules`: administrar periodos de lactancia por permiso (`modo` INICIO|FIN, `fecha_desde`, `fecha_hasta`, `minutos_diarios`). Validar solapamiento (aprovechar constraints del SQL).

* UI en `permisos.html`:

  * Reemplazar el diálogo “Solicitar Permiso” por un formulario con selector de tipo (LSG/Lactancia), fechas, modo y minutos (para lactancia), y asociación opcional a un `jobassignment`.

  * Añadir tabla de permisos del usuario con estado, fechas y acciones (editar/cancelar).

  * Añadir gestión de programación de lactancia (lista y edición de periodos por permiso).

* Regla LSG: permitir doble cargo solo si existe LSG aprobado; se apoya en trigger del SQL. La UI mostrará advertencias si intenta crear segundo cargo sin LSG.

**Consolidado mensual**

* Objetivo: vista mensual por usuario con el valor del campo `final` por día.

* Backend a implementar:

  * `GET /api/consolidated-data?anio=YYYY&mes=MM&q=<dni/nombre>`: devuelve, por usuario, un objeto con `dni`, `nombre`, `modalidad`, y campos `d01..d31` con el `final` de `dailyattendances` (vacío si no hay registro). Base: `dailyattendances` + `jobassignments` + `users` como en `ProcessedDataServlet`.

  * `GET /api/consolidated-export?anio=YYYY&mes=MM&...`: genera XLSX/CSV con las mismas columnas.

* UI en `consolidado.html`:

  * Filtros por año/mes y búsqueda DNI/nombre.

  * Tabla con columnas dinámicas del 1 al 31 mostrando `final` y cabecera fija con `dni`, `nombre`, `modalidad`.

  * Botón Exportar que llama al nuevo endpoint.

**Perfiles (Gestión de usuarios)**

* Implementar página admin nueva `perfiles.html` (o ampliar `perfil.html` si se prefiere mantener nombre) con:

  * Tabla OpenUI5 de usuarios (`dni, nombre, apellidos, email, rol, estado`).

  * Diálogo “Nuevo Usuario” y edición inline con validaciones.

  * Reset de contraseña con hash BCrypt.

* Backend:

  * `GET /api/users?q=&estado=`: listar usuarios con filtros.

  * `POST /api/users`: crear usuario (hashear contraseña con `BCryptUtil` en `src/main/java/com/asistenciav2/util/BCryptUtil.java`).

  * `PUT /api/users/:id`: actualizar datos.

  * `POST /api/users/:id/reset-password`: reset de contraseña.

* Seguridad: restringir a rol `ADMIN` (añadir reglas en `SecurityConfig.java:55` bajo `/admin/**` o usar prefijo `/api/admin/*`).

**Ajustes y convenciones**

* Reutilizar utilidades y estilo de `sap.m` ya empleados en las vistas.

* URLs absolutas bajo el contexto `/asistenciaV2r` como en `dashboard_admin.html:294-300`.

* Conexión a Postgres vía `DatabaseConnection.java:34` con credenciales de entorno.

**Verificación**

* Pruebas funcionales end-to-end:

  * Ejecutar `procesarAsistencia.py` desde Procesados y verificar grilla (`/api/processed-data`).

  * Crear permiso Lactancia y programaciones; validar cálculo impacta en `dailyattendances` al reprocesar.

  * Consolidado: cotejar `final` en la grilla con registros de `dailyattendances`.

  * Perfiles: alta/edición y login del nuevo usuario.

* Añadir toasts y mensajes de error coherentes en UI.

