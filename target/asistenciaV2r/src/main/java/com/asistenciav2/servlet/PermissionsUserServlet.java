package com.asistenciav2.servlet;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@WebServlet("/api/permissions-user")
public class PermissionsUserServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");

        Integer userId = getAuthenticatedUserId();
        if (userId == null) {
            resp.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            resp.getWriter().write("{\"success\":false,\"message\":\"No autorizado\"}");
            return;
        }

        String fechaInicioStr = req.getParameter("fechaInicio");
        String fechaFinStr = req.getParameter("fechaFin");

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
            sql.append("WHERE p.estado = 1 AND p.user_id = ? ");

            List<Object> params = new ArrayList<>();
            params.add(userId);

            if (fechaInicioStr != null && !fechaInicioStr.isEmpty()) {
                sql.append("AND p.fechaini >= ? ");
                params.add(java.sql.Date.valueOf(fechaInicioStr));
            }
            if (fechaFinStr != null && !fechaFinStr.isEmpty()) {
                sql.append("AND p.fechaini <= ? ");
                params.add(java.sql.Date.valueOf(fechaFinStr));
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
            e.printStackTrace();
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        }
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }

    private Integer getAuthenticatedUserId() {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication == null || !authentication.isAuthenticated()) {
                return null;
            }
            String username = authentication.getName();
            if (username == null || username.equals("anonymousUser")) {
                return null;
            }

            try (Connection conn = DatabaseConnection.getConnection()) {
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
            }
        } catch (Exception e) {
            System.err.println("Error getting authenticated user ID: " + e.getMessage());
        }
        return null;
    }
}
