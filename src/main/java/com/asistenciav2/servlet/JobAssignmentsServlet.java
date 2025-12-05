package com.asistenciav2.servlet;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

@WebServlet("/api/jobassignments/*")
public class JobAssignmentsServlet extends HttpServlet {

    /**
     * Obtiene el ID del usuario autenticado actualmente.
     * 
     * @param conn Conexión a la base de datos
     * @return ID del usuario autenticado, o null si no está autenticado
     */
    private Integer getAuthenticatedUserId(Connection conn) {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication == null || !authentication.isAuthenticated() ||
                    "anonymousUser".equals(authentication.getPrincipal())) {
                return null;
            }

            String username = authentication.getName();

            // Buscar el ID del usuario en la base de datos usando email o dni
            String sql = "SELECT id FROM users WHERE (email = ? OR dni = ?) AND estado = 1 LIMIT 1";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, username);
                ps.setString(2, username);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return rs.getInt("id");
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("Error obteniendo ID de usuario autenticado: " + e.getMessage());
            e.printStackTrace();
        }
        return null;
    }

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String userIdStr = req.getParameter("userId");
        List<Map<String, Object>> out = new ArrayList<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            StringBuilder sql = new StringBuilder(
                    "SELECT ja.id, ja.user_id, ja.modalidad, ja.cargo, ja.area, ja.equipo, ja.jefe, ja.fechaini, ja.fechafin, ja.salario, ja.estado, ja.workschedule_id, ws.descripcion AS workschedule, ws.horaini, ws.horafin FROM jobassignments ja JOIN workschedules ws ON ws.id = ja.workschedule_id WHERE ja.estado IN (0,1)");
            List<Object> params = new ArrayList<>();
            if (userIdStr != null && !userIdStr.isEmpty()) {
                sql.append(" AND user_id = ?");
                params.add(Integer.parseInt(userIdStr));
            }
            sql.append(" ORDER BY fechaini DESC");
            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++)
                    ps.setObject(i + 1, params.get(i));
                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    row.put("id", rs.getInt("id"));
                    row.put("userId", rs.getInt("user_id"));
                    row.put("modalidad", rs.getString("modalidad"));
                    row.put("cargo", rs.getString("cargo"));
                    row.put("area", rs.getString("area"));
                    row.put("equipo", rs.getString("equipo"));
                    row.put("jefe", rs.getString("jefe"));
                    java.sql.Date dIni = rs.getDate("fechaini");
                    row.put("fechaini", dIni != null ? dIni.toString() : null);
                    java.sql.Date dFin = rs.getDate("fechafin");
                    row.put("fechafin", dFin != null ? dFin.toString() : null);
                    row.put("salario", rs.getObject("salario"));
                    row.put("estado", rs.getInt("estado"));
                    row.put("workschedule_id", rs.getInt("workschedule_id"));
                    row.put("workschedule", rs.getString("workschedule"));
                    row.put("horaini", String.valueOf(rs.getTime("horaini")));
                    row.put("horafin", String.valueOf(rs.getTime("horafin")));
                    out.add(row);
                }
            }
        } catch (Exception e) {
        }
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");

        // Check if this is an update or delete operation based on path or parameters
        String pathInfo = req.getPathInfo();
        String action = req.getParameter("action");
        String idStr = req.getParameter("id");

        // If we have an ID and it's an update/delete operation, handle it
        if (idStr != null && !idStr.isEmpty()) {
            if ("update".equals(action) || pathInfo != null && pathInfo.contains("update")) {
                handleUpdate(req, resp);
                return;
            } else if ("delete".equals(action) || pathInfo != null && pathInfo.contains("delete")) {
                handleDelete(req, resp);
                return;
            }
        }

        // Otherwise, proceed with normal creation
        String userIdStr = req.getParameter("userId");
        String modalidad = req.getParameter("modalidad");
        String cargo = req.getParameter("cargo");
        String area = req.getParameter("area");
        String equipo = req.getParameter("equipo");
        String jefe = req.getParameter("jefe");
        String fechainiStr = req.getParameter("fechaini");
        String fechafinStr = req.getParameter("fechafin");
        String salarioStr = req.getParameter("salario");
        String observaciones = req.getParameter("observaciones");
        String wsIdStr = req.getParameter("workscheduleId");

        // Debug: Log all parameters for assignment creation
        System.out.println("=== CREATE JOB ASSIGNMENT ===");
        System.out.println("userId: " + userIdStr);
        System.out.println("modalidad: " + modalidad);
        System.out.println("cargo: " + cargo);
        System.out.println("area: " + area);
        System.out.println("equipo: " + equipo);
        System.out.println("jefe: " + jefe);
        System.out.println("fechaini: " + fechainiStr);
        System.out.println("fechafin: " + fechafinStr);
        System.out.println("salario: " + salarioStr);
        System.out.println("observaciones: " + observaciones);
        System.out.println("workscheduleId: " + wsIdStr);
        System.out.println("========================================");

        try (Connection conn = DatabaseConnection.getConnection()) {
            if (userIdStr == null || userIdStr.isEmpty() || "undefined".equals(userIdStr))
                throw new IllegalArgumentException("Falta userId");
            if (modalidad == null || modalidad.isEmpty() || "undefined".equals(modalidad))
                throw new IllegalArgumentException("Falta modalidad");
            if (cargo == null || cargo.isEmpty() || "undefined".equals(cargo))
                throw new IllegalArgumentException("Falta cargo");
            if (area == null || area.isEmpty() || "undefined".equals(area))
                throw new IllegalArgumentException("Falta area");
            if (fechainiStr == null || fechainiStr.isEmpty() || "undefined".equals(fechainiStr))
                throw new IllegalArgumentException("Falta fecha de inicio");
            if (wsIdStr == null || wsIdStr.isEmpty() || "undefined".equals(wsIdStr) || "null".equals(wsIdStr))
                throw new IllegalArgumentException("Seleccione un horario");

            Integer userId;
            try {
                userId = Integer.parseInt(userIdStr);
            } catch (NumberFormatException e) {
                throw new IllegalArgumentException("userId inválido: " + userIdStr);
            }

            Integer wsId;
            try {
                wsId = Integer.parseInt(wsIdStr);
            } catch (NumberFormatException e) {
                throw new IllegalArgumentException("workscheduleId inválido: " + wsIdStr);
            }

            java.sql.Date fechaini;
            try {
                fechaini = java.sql.Date.valueOf(fechainiStr);
            } catch (IllegalArgumentException e) {
                throw new IllegalArgumentException(
                        "Formato de fecha de inicio inválido: " + fechainiStr + ". Use formato YYYY-MM-DD");
            }

            java.sql.Date fechafin = null;
            if (fechafinStr != null && !fechafinStr.isEmpty() && !"undefined".equals(fechafinStr)
                    && !"null".equals(fechafinStr)) {
                try {
                    fechafin = java.sql.Date.valueOf(fechafinStr);
                } catch (IllegalArgumentException e) {
                    throw new IllegalArgumentException(
                            "Formato de fecha de fin inválido: " + fechafinStr + ". Use formato YYYY-MM-DD");
                }
            }
            // Handle optional fields - convert empty/undefined to null
            if (equipo != null && (equipo.isEmpty() || "undefined".equals(equipo))) {
                equipo = null;
            }
            if (jefe != null && (jefe.isEmpty() || "undefined".equals(jefe))) {
                jefe = null;
            }

            // Handle observaciones field
            if (observaciones != null && (observaciones.isEmpty() || "undefined".equals(observaciones))) {
                observaciones = null;
            }

            // Validate salario if provided
            java.math.BigDecimal salario = null;
            if (salarioStr != null && !salarioStr.isEmpty() && !"undefined".equals(salarioStr)
                    && !"null".equals(salarioStr)) {
                try {
                    salario = new java.math.BigDecimal(salarioStr);
                } catch (NumberFormatException e) {
                    throw new IllegalArgumentException("Salario inválido: " + salarioStr);
                }
            }

            // Verificar si el usuario ya tiene cargos VIGENTES que se solapen con el nuevo
            // cargo
            // Solo se requiere LSG si hay cargos VIGENTES (no terminados) que se solapen
            java.sql.Date fechaInicio = fechaini;
            java.sql.Date fechaFin = fechafin != null ? fechafin : java.sql.Date.valueOf("2099-12-31");

            System.out.println("=== VALIDACIÓN DE CARGOS PARA USUARIO " + userId + " ===");
            System.out.println("Fecha inicio nuevo cargo: " + fechaInicio);
            System.out.println("Fecha fin nuevo cargo: " + fechaFin);

            boolean tieneCargosActivosSolapados = false;

            // Buscar cargos VIGENTES que se solapen con el nuevo cargo
            // Un cargo está vigente y se solapa si:
            // 1. estado = 1 (activo)
            // 2. Hay solapamiento de fechas:
            // (StartA <= EndB) and (EndA >= StartB)
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT COUNT(*) FROM jobassignments " +
                            "WHERE user_id = ? AND estado = 1 " +
                            "AND id != ? " + // Excluir el mismo cargo si es una actualización (aunque aquí es create,
                                             // por seguridad)
                            "AND fechaini <= ? " + // Cargo existente inicia antes o cuando termina el nuevo
                            "AND COALESCE(fechafin, '2099-12-31') >= ?")) { // Cargo existente termina después o cuando
                                                                            // inicia el nuevo
                ps.setInt(1, userId);
                ps.setInt(2, -1); // ID a excluir (ninguno en create)
                ps.setDate(3, fechaFin);
                ps.setDate(4, fechaInicio);
                ResultSet rs = ps.executeQuery();
                if (rs.next()) {
                    int count = rs.getInt(1);
                    tieneCargosActivosSolapados = (count > 0);
                    System.out.println("Cargos VIGENTES que se solapan: " + count);
                }
            }

            System.out.println(
                    "Usuario ID: " + userId + " - Tiene cargos activos solapados: " + tieneCargosActivosSolapados);

            // Solo verificar LSG si hay cargos activos que se solapen
            if (tieneCargosActivosSolapados) {
                boolean tieneLSG = false;
                // Verificar si tiene permiso LSG activo que cubra el periodo del solapamiento
                // El permiso LSG debe estar aprobado (estado=1) y permitir doble cargo
                try (PreparedStatement ps = conn.prepareStatement(
                        "SELECT 1 FROM permissions p " +
                                "JOIN permissiontypes pt ON pt.id = p.permissiontype_id " +
                                "WHERE pt.codigo = 'LSG' AND pt.permite_doble_cargo = TRUE " +
                                "AND p.estado = 1 AND p.user_id = ? " +
                                "AND p.fechaini <= ? AND p.fechafin >= ? LIMIT 1")) {
                    ps.setInt(1, userId);
                    ps.setDate(2, fechaFin); // El permiso debe iniciar antes de que termine el cargo
                    ps.setDate(3, fechaInicio); // El permiso debe terminar después de que inicie el cargo
                    // Nota: Esta validación verifica si hay ALGUN solapamiento con LSG.
                    // Para ser más estrictos, deberíamos verificar si el LSG cubre TODO el periodo,
                    // pero la regla de negocio usualmente es tener el permiso vigente.
                    ResultSet rs = ps.executeQuery();
                    if (rs.next()) {
                        tieneLSG = true;
                    }
                }

                if (!tieneLSG) {
                    throw new IllegalArgumentException(
                            "No se permite tener dos cargos simultáneos sin permiso LSG activo. Debe tener un permiso LSG aprobado para asignar un nuevo cargo mientras mantiene uno vigente.");
                }
            }
            String sql = "INSERT INTO jobassignments (modalidad, cargo, area, equipo, jefe, fechaini, fechafin, salario, observaciones, estado, user_id, workschedule_id, usercrea, usermod) VALUES (?,?,?,?,?,?,?,?,?,1,?,?,?,?)";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, modalidad);
                ps.setString(2, cargo);
                ps.setString(3, area);
                if (equipo != null && !equipo.trim().isEmpty()) {
                    ps.setString(4, equipo);
                } else {
                    ps.setNull(4, Types.VARCHAR);
                }
                if (jefe != null && !jefe.trim().isEmpty()) {
                    ps.setString(5, jefe);
                } else {
                    ps.setNull(5, Types.VARCHAR);
                }
                ps.setDate(6, fechaini);
                if (fechafin == null) {
                    ps.setNull(7, Types.DATE);
                } else {
                    ps.setDate(7, fechafin);
                }
                if (salario != null) {
                    ps.setBigDecimal(8, salario);
                } else {
                    ps.setNull(8, Types.DECIMAL);
                }
                if (observaciones != null && !observaciones.trim().isEmpty()) {
                    ps.setString(9, observaciones);
                } else {
                    ps.setNull(9, Types.VARCHAR);
                }
                ps.setInt(10, userId);
                ps.setInt(11, wsId);

                // Obtener el ID del usuario administrador autenticado
                Integer adminUserId = getAuthenticatedUserId(conn);
                if (adminUserId == null) {
                    adminUserId = userId; // Fallback al userId si no se puede obtener el admin
                }

                ps.setInt(12, adminUserId); // usercrea - ID del admin que crea
                ps.setInt(13, adminUserId); // usermod - ID del admin que modifica
                ps.executeUpdate();
            }
            resp.setContentType("application/json");
            resp.setCharacterEncoding("UTF-8");
            resp.getWriter().write("{\"success\":true,\"message\":\"Trabajo asignado\"}");
        } catch (SQLException e) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.setContentType("application/json");
            String msg = e.getMessage();
            ObjectMapper mapper = new ObjectMapper();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("success", false);

            System.err.println("=== ERROR CREATING JOB ASSIGNMENT (SQLException) ===");
            System.err.println("Error type: " + e.getClass().getSimpleName());
            System.err.println("SQL State: " + e.getSQLState());
            System.err.println("Error Code: " + e.getErrorCode());
            System.err.println("Error message: " + msg);
            e.printStackTrace();

            // Capturar mensajes del trigger de la base de datos
            if (msg != null) {
                if (msg.contains("No se permite tener dos cargos simultáneos")) {
                    out.put("message", msg);
                } else if (msg.contains("LSG")) {
                    out.put("message",
                            "No se permite tener dos cargos simultáneos sin LSG aprobado. Debe crear primero un permiso LSG que cubra el período del nuevo cargo.");
                } else if (msg.contains("violates") || msg.contains("constraint")) {
                    out.put("message", "Error de validación: " + msg);
                } else {
                    out.put("message", "Error de base de datos: " + msg);
                }
            } else {
                out.put("message", "Error asignando trabajo. Verifique los datos ingresados.");
            }
            resp.getWriter().write(mapper.writeValueAsString(out));
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.setContentType("application/json");
            String msg = e.getMessage();
            ObjectMapper mapper = new ObjectMapper();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("success", false);

            System.err.println("=== ERROR CREATING JOB ASSIGNMENT ===");
            System.err.println("Error type: " + e.getClass().getSimpleName());
            System.err.println("Error message: " + msg);
            e.printStackTrace();

            // Provide more specific error messages
            String errorMessage = "Error asignando trabajo";
            if (msg != null && !msg.isEmpty()) {
                if (msg.contains("LSG") || msg.contains("dos cargos simultáneos")) {
                    errorMessage = msg;
                } else if (msg.contains("undefined") || msg.contains("Falta")) {
                    errorMessage = msg;
                } else if (msg.contains("format") || msg.contains("parse") || msg.contains("NumberFormat")) {
                    errorMessage = "Error de formato: " + msg;
                } else if (msg.contains("IllegalArgument")) {
                    errorMessage = msg;
                } else {
                    errorMessage = msg;
                }
            } else if (e.getCause() != null && e.getCause().getMessage() != null) {
                errorMessage = e.getCause().getMessage();
            } else {
                errorMessage = "Error inesperado: " + e.getClass().getSimpleName();
            }

            out.put("message", errorMessage);
            System.err.println("Enviando mensaje de error al cliente: " + errorMessage);
            resp.getWriter().write(mapper.writeValueAsString(out));
        }
    }

    private void handleUpdate(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String idStr = req.getParameter("id");
        String userIdStr = req.getParameter("userId");
        String modalidad = req.getParameter("modalidad");
        String cargo = req.getParameter("cargo");
        String area = req.getParameter("area");
        String equipo = req.getParameter("equipo");
        String jefe = req.getParameter("jefe");
        String fechainiStr = req.getParameter("fechaini");
        String fechafinStr = req.getParameter("fechafin");
        String salarioStr = req.getParameter("salario");
        String wsIdStr = req.getParameter("workscheduleId");
        String estadoStr = req.getParameter("estado"); // Agregar estado

        // Debug: Log all parameters
        System.out.println("=== UPDATE JOB ASSIGNMENT ===");
        System.out.println("id: " + idStr);
        System.out.println("userId: " + userIdStr);
        System.out.println("modalidad: " + modalidad);
        System.out.println("cargo: " + cargo);
        System.out.println("area: " + area);
        System.out.println("equipo: " + equipo);
        System.out.println("jefe: " + jefe);
        System.out.println("fechaini: " + fechainiStr);
        System.out.println("fechafin: " + fechafinStr);
        System.out.println("salario: " + salarioStr);
        System.out.println("workscheduleId: " + wsIdStr);
        System.out.println("estado: " + estadoStr); // Log estado

        // Additional debug: check for undefined values that might cause parsing issues
        if ("undefined".equals(idStr) || "undefined".equals(userIdStr) || "undefined".equals(wsIdStr)) {
            System.out.println("WARNING: Found 'undefined' string in critical fields!");
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            if (idStr == null || idStr.isEmpty())
                throw new IllegalArgumentException("Falta id de asignación");
            if (userIdStr == null || userIdStr.isEmpty())
                throw new IllegalArgumentException("Falta userId");
            if (modalidad == null || modalidad.isEmpty())
                throw new IllegalArgumentException("Falta modalidad");
            if (cargo == null || cargo.isEmpty())
                throw new IllegalArgumentException("Falta cargo");
            if (area == null || area.isEmpty())
                throw new IllegalArgumentException("Falta area");
            if (fechainiStr == null || fechainiStr.isEmpty())
                throw new IllegalArgumentException("Falta fecha de inicio");
            if (wsIdStr == null || wsIdStr.isEmpty() || "undefined".equals(wsIdStr) || "null".equals(wsIdStr))
                throw new IllegalArgumentException("Falta horario o horario inválido");

            Integer id = Integer.parseInt(idStr);
            Integer userId = Integer.parseInt(userIdStr);

            // Validate wsIdStr before parsing
            Integer wsId;
            try {
                wsId = Integer.parseInt(wsIdStr);
            } catch (NumberFormatException e) {
                throw new IllegalArgumentException("ID de horario inválido: " + wsIdStr);
            }

            // Parse estado (default to 1 if not provided)
            Integer estado = 1;
            if (estadoStr != null && !estadoStr.isEmpty() && !"undefined".equals(estadoStr)) {
                try {
                    estado = Integer.parseInt(estadoStr);
                } catch (NumberFormatException e) {
                    System.out.println("WARNING: Invalid estado value '" + estadoStr + "', using default 1");
                }
            }

            // Handle optional fields - convert empty/undefined to null
            if (equipo != null && (equipo.isEmpty() || "undefined".equals(equipo))) {
                equipo = null;
            }
            if (jefe != null && (jefe.isEmpty() || "undefined".equals(jefe))) {
                jefe = null;
            }

            // Validate salario if provided
            java.math.BigDecimal salario = null;
            if (salarioStr != null && !salarioStr.isEmpty() && !"undefined".equals(salarioStr)
                    && !"null".equals(salarioStr)) {
                try {
                    salario = new java.math.BigDecimal(salarioStr);
                } catch (NumberFormatException e) {
                    throw new IllegalArgumentException("Salario inválido: " + salarioStr);
                }
            }

            java.sql.Date fechaini = java.sql.Date.valueOf(fechainiStr);
            java.sql.Date fechafin = null;
            if (fechafinStr != null && !fechafinStr.isEmpty() && !"undefined".equals(fechafinStr)
                    && !"null".equals(fechafinStr)) {
                fechafin = java.sql.Date.valueOf(fechafinStr);
            }

            // Incluir estado y usermod en el UPDATE
            String sql = "UPDATE jobassignments SET modalidad=?, cargo=?, area=?, equipo=?, jefe=?, fechaini=?, fechafin=?, salario=?, workschedule_id=?, estado=?, usermod=? WHERE id=? AND user_id=?";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, modalidad);
                ps.setString(2, cargo);
                ps.setString(3, area);
                if (equipo != null)
                    ps.setString(4, equipo);
                else
                    ps.setNull(4, Types.VARCHAR);
                if (jefe != null)
                    ps.setString(5, jefe);
                else
                    ps.setNull(5, Types.VARCHAR);
                ps.setDate(6, fechaini);
                if (fechafin == null)
                    ps.setNull(7, Types.DATE);
                else
                    ps.setDate(7, fechafin);
                if (salario != null)
                    ps.setBigDecimal(8, salario);
                else
                    ps.setNull(8, Types.DECIMAL);
                ps.setInt(9, wsId);
                ps.setInt(10, estado); // Agregar estado

                // Obtener el ID del usuario administrador autenticado
                Integer adminUserId = getAuthenticatedUserId(conn);
                if (adminUserId == null) {
                    adminUserId = userId; // Fallback al userId si no se puede obtener el admin
                }

                ps.setInt(11, adminUserId); // usermod - ID del admin que modifica
                ps.setInt(12, id);
                ps.setInt(13, userId);

                int rows = ps.executeUpdate();
                if (rows == 0) {
                    throw new IllegalArgumentException("No se encontró la asignación o no pertenece al usuario");
                }

                String message = estado == 0 ? "Asignación eliminada" : "Asignación actualizada";
                resp.getWriter().write("{\"success\":true,\"message\":\"" + message + "\"}");
            }
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.setContentType("application/json");
            String msg = e.getMessage();
            ObjectMapper mapper = new ObjectMapper();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("success", false);
            out.put("message", msg != null ? msg : "Error actualizando asignación");
            resp.getWriter().write(mapper.writeValueAsString(out));
        }
    }

    private void handleDelete(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String idStr = req.getParameter("id");

        try (Connection conn = DatabaseConnection.getConnection()) {
            if (idStr == null || idStr.isEmpty())
                throw new IllegalArgumentException("Falta id de asignación");

            Integer id = Integer.parseInt(idStr);

            // Verificar que la asignación existe
            try (PreparedStatement ps = conn
                    .prepareStatement("SELECT id FROM jobassignments WHERE id = ? AND estado IN (0,1)")) {
                ps.setInt(1, id);
                ResultSet rs = ps.executeQuery();
                if (!rs.next()) {
                    throw new IllegalArgumentException("Asignación no encontrada");
                }
            }

            // Actualizar estado a eliminado (estado = 2) en lugar de borrar físicamente
            String sql = "UPDATE jobassignments SET estado = 2 WHERE id = ?";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setInt(1, id);
                int rows = ps.executeUpdate();
                if (rows == 0) {
                    throw new IllegalArgumentException("No se pudo eliminar la asignación");
                }
                resp.getWriter().write("{\"success\":true,\"message\":\"Asignación eliminada\"}");
            }
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.setContentType("application/json");
            String msg = e.getMessage();
            ObjectMapper mapper = new ObjectMapper();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("success", false);
            out.put("message", msg != null ? msg : "Error eliminando asignación");
            resp.getWriter().write(mapper.writeValueAsString(out));
        }
    }
}