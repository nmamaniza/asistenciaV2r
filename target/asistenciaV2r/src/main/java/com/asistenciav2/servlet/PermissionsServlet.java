package com.asistenciav2.servlet;

import java.io.BufferedReader;
import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@WebServlet("/api/permissions")
public class PermissionsServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String userIdStr = req.getParameter("userId");
        List<Map<String, Object>> out = new ArrayList<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            StringBuilder sql = new StringBuilder();
            sql.append("SELECT p.id, u.dni, COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre, ");
            sql.append("pt.codigo, pt.descripcion, p.fechaini, p.fechafin, p.estado, p.jobassignment_id, ");
            sql.append("COALESCE(ja.cargo, 'Sin cargo') AS cargo, ");
            sql.append("ls.modo, ");
            sql.append("ucrea.dni AS usercrea_dni, ");
            sql.append("umod.dni AS usermod_dni, ");
            sql.append("p.created_at, p.updated_at ");
            sql.append("FROM permissions p JOIN permissiontypes pt ON pt.id = p.permissiontype_id ");
            sql.append("JOIN users u ON u.id = p.user_id ");
            sql.append("LEFT JOIN jobassignments ja ON ja.id = p.jobassignment_id ");
            sql.append("LEFT JOIN lactation_schedules ls ON ls.permission_id = p.id AND ls.estado = 1 ");
            sql.append("LEFT JOIN users ucrea ON ucrea.id = p.usercrea ");
            sql.append("LEFT JOIN users umod ON umod.id = p.usermod ");
            sql.append("WHERE p.estado = 1 ");
            List<Object> params = new ArrayList<>();
            if (userIdStr != null && !userIdStr.isEmpty()) {
                sql.append("AND p.user_id = ? ");
                params.add(Integer.parseInt(userIdStr));
            }
            sql.append("ORDER BY p.fechaini DESC");
            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++)
                    ps.setObject(i + 1, params.get(i));
                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    row.put("id", rs.getInt("id"));
                    row.put("dni", rs.getString("dni"));
                    row.put("nombre", rs.getString("nombre"));
                    row.put("codigo", rs.getString("codigo"));
                    row.put("descripcion", rs.getString("descripcion"));
                    row.put("fechaini", rs.getDate("fechaini"));
                    row.put("fechafin", rs.getDate("fechafin"));
                    row.put("estado", rs.getInt("estado"));
                    row.put("jobassignment_id", rs.getObject("jobassignment_id"));
                    row.put("cargo", rs.getString("cargo"));
                    row.put("modo", rs.getString("modo"));
                    row.put("usercrea_dni", rs.getString("usercrea_dni"));
                    row.put("usermod_dni", rs.getString("usermod_dni"));
                    row.put("created_at", rs.getTimestamp("created_at"));
                    row.put("updated_at", rs.getTimestamp("updated_at"));
                    out.add(row);
                }
            }
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        }
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String userIdStr = req.getParameter("userId");
        String permissionTypeCode = req.getParameter("permissionType");
        String fechainiStr = req.getParameter("fechaini");
        String fechafinStr = req.getParameter("fechafin");
        String jobIdStr = req.getParameter("jobassignmentId");

        // Debug logging
        System.out.println("PermissionsServlet.doPost - Parameters received:");
        System.out.println("  userId: " + userIdStr);
        System.out.println("  permissionType: " + permissionTypeCode);
        System.out.println("  fechaini: " + fechainiStr);
        System.out.println("  fechafin: " + fechafinStr);
        System.out.println("  jobassignmentId: " + jobIdStr);

        // Validación de parámetros requeridos
        if (fechainiStr == null || fechainiStr.isEmpty()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"La fecha de inicio es requerida\"}");
            return;
        }
        if (permissionTypeCode == null || permissionTypeCode.isEmpty()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"El tipo de permiso es requerido\"}");
            return;
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            Integer userId;
            if (userIdStr != null && !userIdStr.isEmpty()) {
                userId = Integer.parseInt(userIdStr);
            } else {
                Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
                String username = authentication != null ? authentication.getName() : null;
                if (username == null) {
                    resp.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                    resp.getWriter().write("{\"success\":false,\"message\":\"No autorizado\"}");
                    return;
                }
                try (PreparedStatement ps = conn
                        .prepareStatement("SELECT id FROM users WHERE (email = ? OR dni = ?) AND estado=1 LIMIT 1")) {
                    ps.setString(1, username);
                    ps.setString(2, username);
                    ResultSet rs = ps.executeQuery();
                    if (rs.next()) {
                        userId = rs.getInt(1);
                    } else {
                        resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
                        resp.getWriter().write("{\"success\":false,\"message\":\"Usuario no encontrado\"}");
                        return;
                    }
                }
            }
            java.sql.Date fechaini = null;
            java.sql.Date fechafin = null;

            try {
                // Try to parse as date string first (YYYY-MM-DD format)
                fechaini = java.sql.Date.valueOf(fechainiStr);
            } catch (IllegalArgumentException e) {
                // If that fails, try to parse as timestamp
                try {
                    long timestamp = Long.parseLong(fechainiStr);
                    // Convert from milliseconds to seconds if needed
                    if (timestamp > 9999999999L) {
                        timestamp = timestamp / 1000;
                    }
                    fechaini = new java.sql.Date(timestamp * 1000);
                } catch (NumberFormatException e2) {
                    throw new Exception("Formato de fecha inválido para fechaini: " + fechainiStr);
                }
            }

            if (fechafinStr != null && !fechafinStr.isEmpty()) {
                try {
                    fechafin = java.sql.Date.valueOf(fechafinStr);
                } catch (IllegalArgumentException e) {
                    try {
                        long timestamp = Long.parseLong(fechafinStr);
                        if (timestamp > 9999999999L) {
                            timestamp = timestamp / 1000;
                        }
                        fechafin = new java.sql.Date(timestamp * 1000);
                    } catch (NumberFormatException e2) {
                        throw new Exception("Formato de fecha inválido para fechafin: " + fechafinStr);
                    }
                }
            }
            Integer jobId = (jobIdStr != null && !jobIdStr.isEmpty()) ? Integer.parseInt(jobIdStr) : null;
            Integer typeId = null;
            String abrevia = null;
            String descripcion = null;

            try (PreparedStatement ps = conn
                    .prepareStatement(
                            "SELECT id, codigo, descripcion FROM permissiontypes WHERE codigo = ? AND estado = 1")) {
                ps.setString(1, permissionTypeCode);
                ResultSet rs = ps.executeQuery();
                if (rs.next()) {
                    typeId = rs.getInt("id");
                    abrevia = rs.getString("codigo");
                    descripcion = rs.getString("descripcion");
                }
                System.out.println("Permission type lookup result: " + typeId + " for code: " + permissionTypeCode);
            }
            if (typeId == null) {
                System.out.println("Permission type not found for code: " + permissionTypeCode);
                resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
                resp.getWriter().write("{\"success\":false,\"message\":\"Tipo de permiso inválido\"}");
                return;
            }
            // Obtener ID del usuario que crea el permiso
            Integer adminUserId = getAuthenticatedUserId(conn);
            if (adminUserId == null) {
                adminUserId = userId; // Fallback: usar el mismo usuario del permiso
            }

            String sql = "INSERT INTO permissions (permissiontype_id, fechaini, fechafin, user_id, jobassignment_id, estado, usercrea, usermod, abrevia, descripcion) VALUES (?,?,?,?,?,1,?,?,?,?)";
            Integer newId = null;
            System.out.println("Executing INSERT with params: typeId=" + typeId + ", fechaini=" + fechaini
                    + ", fechafin=" + fechafin + ", userId=" + userId + ", jobId=" + jobId + ", adminUserId="
                    + adminUserId + ", abrevia=" + abrevia + ", descripcion=" + descripcion);
            try (PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
                ps.setInt(1, typeId);
                ps.setDate(2, fechaini);
                if (fechafin == null)
                    ps.setNull(3, java.sql.Types.DATE);
                else
                    ps.setDate(3, fechafin);
                ps.setInt(4, userId);
                if (jobId == null)
                    ps.setNull(5, java.sql.Types.INTEGER);
                else
                    ps.setInt(5, jobId);
                ps.setInt(6, adminUserId);
                ps.setInt(7, adminUserId);
                ps.setString(8, abrevia);
                ps.setString(9, descripcion);
                ps.executeUpdate();
                try (ResultSet gk = ps.getGeneratedKeys()) {
                    if (gk.next())
                        newId = gk.getInt(1);
                }
            }
            ObjectMapper mapper = new ObjectMapper();
            java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
            out.put("success", true);
            out.put("message", "Permiso creado");
            if (newId != null)
                out.put("id", newId);
            resp.getWriter().write(mapper.writeValueAsString(out));
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            System.err.println("Error en PermissionsServlet.doPost: " + e.getMessage());
            e.printStackTrace();
            resp.getWriter().write("{\"success\":false,\"message\":\"Error creando permiso: \" + e.getMessage()}");
        }
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");

        // Leer parámetros del body para peticiones PUT
        Map<String, String> params = new HashMap<>();
        try (BufferedReader reader = req.getReader()) {
            String body = reader.lines().collect(Collectors.joining());
            if (body != null && !body.isEmpty()) {
                String[] pairs = body.split("&");
                for (String pair : pairs) {
                    String[] keyValue = pair.split("=", 2);
                    if (keyValue.length == 2) {
                        params.put(
                                java.net.URLDecoder.decode(keyValue[0], "UTF-8"),
                                java.net.URLDecoder.decode(keyValue[1], "UTF-8"));
                    }
                }
            }
        }

        String idStr = params.get("id");
        String permissionTypeCode = params.get("permissionType");
        String fechainiStr = params.get("fechaini");
        String fechafinStr = params.get("fechafin");
        String jobIdStr = params.get("jobassignmentId");

        if (idStr == null || idStr.isEmpty()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"ID de permiso requerido\"}");
            return;
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            Integer permId = Integer.parseInt(idStr);
            java.sql.Date fechaini = null;
            java.sql.Date fechafin = null;

            if (fechainiStr != null && !fechainiStr.isEmpty()) {
                try {
                    fechaini = java.sql.Date.valueOf(fechainiStr);
                } catch (IllegalArgumentException e) {
                    try {
                        long timestamp = Long.parseLong(fechainiStr);
                        if (timestamp > 9999999999L)
                            timestamp = timestamp / 1000;
                        fechaini = new java.sql.Date(timestamp * 1000);
                    } catch (NumberFormatException e2) {
                        throw new Exception("Formato de fecha inválido para fechaini: " + fechainiStr);
                    }
                }
            }

            if (fechafinStr != null && !fechafinStr.isEmpty()) {
                try {
                    fechafin = java.sql.Date.valueOf(fechafinStr);
                } catch (IllegalArgumentException e) {
                    try {
                        long timestamp = Long.parseLong(fechafinStr);
                        if (timestamp > 9999999999L)
                            timestamp = timestamp / 1000;
                        fechafin = new java.sql.Date(timestamp * 1000);
                    } catch (NumberFormatException e2) {
                        throw new Exception("Formato de fecha inválido para fechafin: " + fechafinStr);
                    }
                }
            }

            Integer typeId = null;
            String abrevia = null;
            String descripcion = null;

            if (permissionTypeCode != null && !permissionTypeCode.isEmpty()) {
                try (PreparedStatement ps = conn
                        .prepareStatement(
                                "SELECT id, codigo, descripcion FROM permissiontypes WHERE codigo = ? AND estado = 1")) {
                    ps.setString(1, permissionTypeCode);
                    ResultSet rs = ps.executeQuery();
                    if (rs.next()) {
                        typeId = rs.getInt("id");
                        abrevia = rs.getString("codigo");
                        descripcion = rs.getString("descripcion");
                    }
                }
                if (typeId == null) {
                    resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
                    resp.getWriter().write("{\"success\":false,\"message\":\"Tipo de permiso inválido\"}");
                    return;
                }
            }

            // Obtener ID del usuario que modifica el permiso
            Integer adminUserId = getAuthenticatedUserId(conn);

            StringBuilder sql = new StringBuilder("UPDATE permissions SET updated_at = CURRENT_TIMESTAMP");
            List<Object> sqlParams = new ArrayList<>();

            if (typeId != null) {
                sql.append(", permissiontype_id = ?");
                sqlParams.add(typeId);
                sql.append(", abrevia = ?");
                sqlParams.add(abrevia);
                sql.append(", descripcion = ?");
                sqlParams.add(descripcion);
            }
            if (fechaini != null) {
                sql.append(", fechaini = ?");
                sqlParams.add(fechaini);
            }
            if (fechafin != null) {
                sql.append(", fechafin = ?");
                sqlParams.add(fechafin);
            } else if (fechafinStr != null && fechafinStr.isEmpty()) {
                sql.append(", fechafin = NULL");
            }
            if (jobIdStr != null) {
                if (jobIdStr.isEmpty()) {
                    sql.append(", jobassignment_id = NULL");
                } else {
                    sql.append(", jobassignment_id = ?");
                    sqlParams.add(Integer.parseInt(jobIdStr));
                }
            }

            // Manejo del estado para soft delete
            String estadoStr = params.get("estado");
            if (estadoStr != null && !estadoStr.isEmpty()) {
                sql.append(", estado = ?");
                sqlParams.add(Integer.parseInt(estadoStr));
            }

            // Agregar usermod
            if (adminUserId != null) {
                sql.append(", usermod = ?");
                sqlParams.add(adminUserId);
            }

            sql.append(" WHERE id = ?");
            sqlParams.add(permId);

            // Check if we need to deactivate lactation schedules
            // This happens when: 1) Permission is being deleted (estado=0), or 2)
            // Permission type is changing from LACTANCIA
            boolean shouldDeactivateLactation = false;

            if (estadoStr != null && estadoStr.equals("0")) {
                // Permission is being deleted
                shouldDeactivateLactation = true;
            } else if (permissionTypeCode != null && !permissionTypeCode.isEmpty()) {
                // Check if the old permission type was LACTANCIA
                String checkOldTypeSql = "SELECT pt.codigo FROM permissions p JOIN permissiontypes pt ON p.permissiontype_id = pt.id WHERE p.id = ?";
                try (PreparedStatement psCheck = conn.prepareStatement(checkOldTypeSql)) {
                    psCheck.setInt(1, permId);
                    ResultSet rsCheck = psCheck.executeQuery();
                    if (rsCheck.next()) {
                        String oldCodigo = rsCheck.getString("codigo");
                        // If changing from LACTANCIA to something else, deactivate schedules
                        if ("LACTANCIA".equals(oldCodigo) && !permissionTypeCode.equals("LACTANCIA")) {
                            shouldDeactivateLactation = true;
                        }
                    }
                }
            }

            // Deactivate lactation schedules if needed
            if (shouldDeactivateLactation) {
                try {
                    LactationSchedulesServlet.deactivateLactationSchedules(conn, permId, adminUserId);
                } catch (Exception e) {
                    System.err.println("Error deactivating lactation schedules: " + e.getMessage());
                }
            }

            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < sqlParams.size(); i++) {
                    ps.setObject(i + 1, sqlParams.get(i));
                }
                int rows = ps.executeUpdate();
                if (rows == 0) {
                    resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
                    resp.getWriter().write("{\"success\":false,\"message\":\"Permiso no encontrado\"}");
                    return;
                }
            }

            ObjectMapper mapper = new ObjectMapper();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("success", true);
            out.put("message", "Permiso actualizado");
            resp.getWriter().write(mapper.writeValueAsString(out));
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            System.err.println("Error en PermissionsServlet.doPut: " + e.getMessage());
            e.printStackTrace();
            resp.getWriter().write("{\"success\":false,\"message\":\"Error actualizando permiso: "
                    + e.getMessage().replace("\"", "\\\"") + "\"}");
        }
    }

    @Override
    protected void doDelete(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String idStr = req.getParameter("id");

        if (idStr == null || idStr.isEmpty()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"ID de permiso requerido\"}");
            return;
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            Integer permId = Integer.parseInt(idStr);

            // Obtener ID del usuario autenticado
            Integer adminUserId = getAuthenticatedUserId(conn);

            // Deactivate lactation schedules if any exist
            try {
                LactationSchedulesServlet.deactivateLactationSchedules(conn, permId, adminUserId);
            } catch (Exception e) {
                System.err.println("Error deactivating lactation schedules: " + e.getMessage());
            }

            // Actualizar estado a 0 (inactivo) en lugar de borrar físicamente
            String sql = "UPDATE permissions SET estado = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setInt(1, permId);
                int rows = ps.executeUpdate();
                if (rows == 0) {
                    resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
                    resp.getWriter().write("{\"success\":false,\"message\":\"Permiso no encontrado\"}");
                    return;
                }
            }

            ObjectMapper mapper = new ObjectMapper();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("success", true);
            out.put("message", "Permiso eliminado");
            resp.getWriter().write(mapper.writeValueAsString(out));
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            System.err.println("Error en PermissionsServlet.doDelete: " + e.getMessage());
            e.printStackTrace();
            resp.getWriter().write("{\"success\":false,\"message\":\"Error eliminando permiso: "
                    + e.getMessage().replace("\"", "\\\"") + "\"}");
        }
    }

    private Integer getAuthenticatedUserId(Connection conn) {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication == null || !authentication.isAuthenticated()) {
                return null;
            }
            String username = authentication.getName();
            if (username == null || username.equals("anonymousUser")) {
                return null;
            }

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
            System.err.println("Error getting authenticated user ID: " + e.getMessage());
        }
        return null;
    }
}