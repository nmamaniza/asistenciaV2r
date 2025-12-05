package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.*;
import java.util.*;

@WebServlet("/api/lactation-schedules")
public class LactationSchedulesServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String permissionIdStr = req.getParameter("permissionId");
        List<Map<String, Object>> out = new ArrayList<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            StringBuilder sql = new StringBuilder(
                    "SELECT id, permission_id, fecha_desde, fecha_hasta, modo, minutos_diarios, observaciones, estado FROM lactation_schedules WHERE estado=1");
            List<Object> params = new ArrayList<>();
            if (permissionIdStr != null && !permissionIdStr.isEmpty()) {
                sql.append(" AND permission_id = ?");
                params.add(Integer.parseInt(permissionIdStr));
            }
            sql.append(" ORDER BY fecha_desde ASC");
            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++)
                    ps.setObject(i + 1, params.get(i));
                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    row.put("id", rs.getInt("id"));
                    row.put("permission_id", rs.getInt("permission_id"));
                    row.put("fecha_desde", rs.getDate("fecha_desde"));
                    row.put("fecha_hasta", rs.getDate("fecha_hasta"));
                    row.put("modo", rs.getString("modo"));
                    row.put("minutos_diarios", rs.getInt("minutos_diarios"));
                    row.put("observaciones", rs.getString("observaciones"));
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

        String permissionIdStr = req.getParameter("permissionId");
        String modo = req.getParameter("modo");

        if (permissionIdStr == null || permissionIdStr.isEmpty()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"ID de permiso requerido\"}");
            return;
        }

        if (modo == null || modo.isEmpty()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"Modo requerido\"}");
            return;
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            Integer permissionId = Integer.parseInt(permissionIdStr);

            // Obtener fechas del permiso
            java.sql.Date fechaDesde = null;
            java.sql.Date fechaHasta = null;
            Integer userId = null;

            String sqlPerm = "SELECT fechaini, fechafin, user_id FROM permissions WHERE id = ? AND estado = 1";
            try (PreparedStatement psPerm = conn.prepareStatement(sqlPerm)) {
                psPerm.setInt(1, permissionId);
                ResultSet rs = psPerm.executeQuery();
                if (rs.next()) {
                    fechaDesde = rs.getDate("fechaini");
                    fechaHasta = rs.getDate("fechafin");
                    userId = rs.getInt("user_id");
                } else {
                    resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
                    resp.getWriter().write("{\"success\":false,\"message\":\"Permiso no encontrado\"}");
                    return;
                }
            }

            // Obtener usuario autenticado
            Integer adminUserId = getAuthenticatedUserId(conn);
            if (adminUserId == null) {
                adminUserId = userId; // Fallback: usar el usuario del permiso
            }

            // Check if lactation schedule already exists for this permission
            String checkSql = "SELECT id FROM lactation_schedules WHERE permission_id = ? AND estado = 1";
            Integer scheduleId = null;
            try (PreparedStatement psCheck = conn.prepareStatement(checkSql)) {
                psCheck.setInt(1, permissionId);
                ResultSet rsCheck = psCheck.executeQuery();
                if (rsCheck.next()) {
                    scheduleId = rsCheck.getInt("id");
                }
            }

            if (scheduleId != null) {
                // Update existing schedule
                String updateSql = "UPDATE lactation_schedules SET modo = ?::lactancia_mode, fecha_desde = ?, fecha_hasta = ?, usermod = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?";
                try (PreparedStatement psUpdate = conn.prepareStatement(updateSql)) {
                    psUpdate.setString(1, modo);
                    psUpdate.setDate(2, fechaDesde);
                    if (fechaHasta != null) {
                        psUpdate.setDate(3, fechaHasta);
                    } else {
                        psUpdate.setNull(3, java.sql.Types.DATE);
                    }
                    psUpdate.setInt(4, adminUserId);
                    psUpdate.setInt(5, scheduleId);
                    psUpdate.executeUpdate();
                }
                resp.getWriter().write("{\"success\":true,\"message\":\"Programación de lactancia actualizada\"}");
            } else {
                // Insert new schedule
                String insertSql = "INSERT INTO lactation_schedules (permission_id, fecha_desde, fecha_hasta, modo, usercrea, usermod, estado) VALUES (?,?,?,?::lactancia_mode,?,?,1)";
                try (PreparedStatement psInsert = conn.prepareStatement(insertSql)) {
                    psInsert.setInt(1, permissionId);
                    psInsert.setDate(2, fechaDesde);
                    if (fechaHasta != null) {
                        psInsert.setDate(3, fechaHasta);
                    } else {
                        psInsert.setNull(3, java.sql.Types.DATE);
                    }
                    psInsert.setString(4, modo);
                    psInsert.setInt(5, adminUserId);
                    psInsert.setInt(6, adminUserId);
                    psInsert.executeUpdate();
                }
                resp.getWriter().write("{\"success\":true,\"message\":\"Programación de lactancia creada\"}");
            }
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            System.err.println("Error en LactationSchedulesServlet.doPost: " + e.getMessage());
            e.printStackTrace();
            resp.getWriter()
                    .write("{\"success\":false,\"message\":\"Error en programación: " + e.getMessage() + "\"}");
        }
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");

        // Read parameters from request body
        java.util.Map<String, String> params = new java.util.HashMap<>();
        try (java.io.BufferedReader reader = req.getReader()) {
            String body = reader.lines().collect(java.util.stream.Collectors.joining());
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

        String permissionIdStr = params.get("permissionId");
        String modo = params.get("modo");

        if (permissionIdStr == null || permissionIdStr.isEmpty()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"ID de permiso requerido\"}");
            return;
        }

        if (modo == null || modo.isEmpty()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"Modo requerido\"}");
            return;
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            Integer permissionId = Integer.parseInt(permissionIdStr);

            // Obtener usuario autenticado
            Integer adminUserId = getAuthenticatedUserId(conn);

            // Actualizar o insertar programación de lactancia
            String checkSql = "SELECT id FROM lactation_schedules WHERE permission_id = ? AND estado = 1";
            Integer scheduleId = null;
            try (PreparedStatement psCheck = conn.prepareStatement(checkSql)) {
                psCheck.setInt(1, permissionId);
                ResultSet rs = psCheck.executeQuery();
                if (rs.next()) {
                    scheduleId = rs.getInt("id");
                }
            }

            if (scheduleId != null) {
                // Actualizar existente
                String updateSql = "UPDATE lactation_schedules SET modo = ?::lactancia_mode, usermod = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?";
                try (PreparedStatement psUpdate = conn.prepareStatement(updateSql)) {
                    psUpdate.setString(1, modo);
                    if (adminUserId != null) {
                        psUpdate.setInt(2, adminUserId);
                    } else {
                        psUpdate.setNull(2, java.sql.Types.INTEGER);
                    }
                    psUpdate.setInt(3, scheduleId);
                    psUpdate.executeUpdate();
                }
            } else {
                // Insertar nuevo
                // Obtener fechas del permiso
                java.sql.Date fechaDesde = null;
                java.sql.Date fechaHasta = null;

                String sqlPerm = "SELECT fechaini, fechafin FROM permissions WHERE id = ? AND estado = 1";
                try (PreparedStatement psPerm = conn.prepareStatement(sqlPerm)) {
                    psPerm.setInt(1, permissionId);
                    ResultSet rs = psPerm.executeQuery();
                    if (rs.next()) {
                        fechaDesde = rs.getDate("fechaini");
                        fechaHasta = rs.getDate("fechafin");
                    } else {
                        resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
                        resp.getWriter().write("{\"success\":false,\"message\":\"Permiso no encontrado\"}");
                        return;
                    }
                }

                String insertSql = "INSERT INTO lactation_schedules (permission_id, fecha_desde, fecha_hasta, modo, usercrea, usermod, estado) VALUES (?,?,?,?::lactancia_mode,?,?,1)";
                try (PreparedStatement psInsert = conn.prepareStatement(insertSql)) {
                    psInsert.setInt(1, permissionId);
                    psInsert.setDate(2, fechaDesde);
                    if (fechaHasta != null) {
                        psInsert.setDate(3, fechaHasta);
                    } else {
                        psInsert.setNull(3, java.sql.Types.DATE);
                    }
                    psInsert.setString(4, modo);
                    if (adminUserId != null) {
                        psInsert.setInt(5, adminUserId);
                        psInsert.setInt(6, adminUserId);
                    } else {
                        psInsert.setNull(5, java.sql.Types.INTEGER);
                        psInsert.setNull(6, java.sql.Types.INTEGER);
                    }
                    psInsert.executeUpdate();
                }
            }

            resp.getWriter().write("{\"success\":true,\"message\":\"Programación de lactancia actualizada\"}");
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            System.err.println("Error en LactationSchedulesServlet.doPut: " + e.getMessage());
            e.printStackTrace();
            resp.getWriter()
                    .write("{\"success\":false,\"message\":\"Error actualizando programación: " + e.getMessage()
                            + "\"}");
        }
    }

    /**
     * Deactivate lactation schedules for a given permission
     * 
     * @param conn         Database connection
     * @param permissionId Permission ID
     * @param usermodId    User ID who is making the change
     */
    public static void deactivateLactationSchedules(Connection conn, Integer permissionId, Integer usermodId)
            throws SQLException {
        String sql = "UPDATE lactation_schedules SET estado = 0, usermod = ?, updated_at = CURRENT_TIMESTAMP WHERE permission_id = ? AND estado = 1";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            if (usermodId != null) {
                ps.setInt(1, usermodId);
            } else {
                ps.setNull(1, java.sql.Types.INTEGER);
            }
            ps.setInt(2, permissionId);
            ps.executeUpdate();
        }
    }

    private Integer getAuthenticatedUserId(Connection conn) {
        try {
            org.springframework.security.core.Authentication authentication = org.springframework.security.core.context.SecurityContextHolder
                    .getContext().getAuthentication();
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