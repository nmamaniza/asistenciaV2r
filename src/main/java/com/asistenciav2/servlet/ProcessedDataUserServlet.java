package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.*;
import jakarta.servlet.annotation.WebServlet;
import java.io.IOException;
import java.sql.*;
import java.util.*;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

@WebServlet("/api/processed-data-user")
public class ProcessedDataUserServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");

        // Get authenticated user
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
            sql.append("SELECT da.id, u.dni, COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre, ");
            sql.append("da.fecha, da.obs, da.doc, da.final, da.horaint, ja.cargo, ja.area, ja.modalidad ");
            sql.append("FROM dailyattendances da ");
            sql.append("JOIN jobassignments ja ON ja.id = da.jobassignment_id ");
            sql.append("JOIN users u ON u.id = ja.user_id ");
            sql.append("WHERE da.estado = 1 AND u.id = ? ");

            List<Object> params = new ArrayList<>();
            params.add(userId);

            if (fechaInicioStr != null && !fechaInicioStr.isEmpty()) {
                sql.append("AND da.fecha >= ? ");
                params.add(java.sql.Date.valueOf(fechaInicioStr));
            }
            if (fechaFinStr != null && !fechaFinStr.isEmpty()) {
                sql.append("AND da.fecha <= ? ");
                params.add(java.sql.Date.valueOf(fechaFinStr));
            }

            sql.append("ORDER BY da.fecha DESC, u.dni ASC, ja.cargo ASC LIMIT 2000");

            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setObject(i + 1, params.get(i));
                }
                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    Map<String, Object> row = new HashMap<>();
                    row.put("id", rs.getInt("id"));
                    row.put("dni", rs.getString("dni"));
                    row.put("nombre", rs.getString("nombre"));
                    row.put("fecha", rs.getDate("fecha"));
                    row.put("obs", rs.getString("obs"));
                    row.put("doc", rs.getString("doc"));
                    row.put("final", rs.getString("final"));
                    row.put("horaint", rs.getString("horaint"));
                    row.put("cargo", rs.getString("cargo"));
                    row.put("area", rs.getString("area"));
                    row.put("modalidad", rs.getString("modalidad"));
                    out.add(row);
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        } catch (IllegalArgumentException e) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"Formato de fecha inválido\"}");
            return;
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
