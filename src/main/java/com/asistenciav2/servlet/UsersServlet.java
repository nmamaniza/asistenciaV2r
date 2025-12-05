package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.asistenciav2.util.BCryptUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import java.io.IOException;
import java.sql.*;
import java.util.*;

@WebServlet("/api/users")
public class UsersServlet extends HttpServlet {

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
        }
        return null;
    }

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String q = req.getParameter("q");
        String estadoParam = req.getParameter("estado");
        List<Map<String, Object>> out = new ArrayList<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            StringBuilder sql = new StringBuilder(
                    "SELECT id, dni, nombre, apellidos, email, role, estado FROM users WHERE 1=1");
            List<Object> params = new ArrayList<>();
            if (estadoParam != null && ("0".equals(estadoParam) || "1".equals(estadoParam))) {
                sql.append(" AND estado = ?");
                params.add(Integer.parseInt(estadoParam));
            } else {
                sql.append(" AND estado IN (0,1)");
            }
            if (q != null && !q.isEmpty()) {
                sql.append(" AND (dni LIKE ? OR UPPER(nombre || ' ' || COALESCE(apellidos,'')) LIKE UPPER(?))");
                String pat = "%" + q + "%";
                params.add(pat);
                params.add(pat);
            }
            sql.append(" ORDER BY nombre ASC");
            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++)
                    ps.setObject(i + 1, params.get(i));
                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    row.put("id", rs.getInt("id"));
                    row.put("dni", rs.getString("dni"));
                    row.put("nombre", rs.getString("nombre"));
                    row.put("apellidos", rs.getString("apellidos"));
                    row.put("email", rs.getString("email"));
                    String role = rs.getString("role");
                    String rolOut = (role != null && role.equalsIgnoreCase("administrador")) ? "ADMIN" : "USER";
                    row.put("rol", rolOut);
                    row.put("estado", rs.getInt("estado"));
                    out.add(row);
                }
            }
        } catch (SQLException e) {
            // Log the error for debugging
            System.err.println("[UsersServlet] Database error: " + e.getMessage());
            e.printStackTrace();

            // Return empty array but with proper JSON format
            ObjectMapper mapper = new ObjectMapper();
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            Map<String, Object> errorResponse = new LinkedHashMap<>();
            errorResponse.put("error", "Database error: " + e.getMessage());
            errorResponse.put("users", out);
            resp.getWriter().write(mapper.writeValueAsString(errorResponse));
            return;
        } catch (Exception e) {
            // Catch any other unexpected errors
            System.err.println("[UsersServlet] Unexpected error: " + e.getMessage());
            e.printStackTrace();

            ObjectMapper mapper = new ObjectMapper();
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            Map<String, Object> errorResponse = new LinkedHashMap<>();
            errorResponse.put("error", "Unexpected error: " + e.getMessage());
            errorResponse.put("users", out);
            resp.getWriter().write(mapper.writeValueAsString(errorResponse));
            return;
        }
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String dni = req.getParameter("dni");
        String nombre = req.getParameter("nombre");
        String apellidos = req.getParameter("apellidos");
        String email = req.getParameter("email");
        String password = req.getParameter("password");
        String rolStr = req.getParameter("rol");
        try (Connection conn = DatabaseConnection.getConnection()) {
            String hash = BCryptUtil.hashPassword(password);
            String role = ("ADMIN".equalsIgnoreCase(rolStr)) ? "administrador" : "usuario";

            // Obtener el ID del usuario administrador autenticado
            Integer adminUserId = getAuthenticatedUserId(conn);

            // Fallback: si no hay usuario autenticado en el contexto, buscar un admin en la
            // BD
            if (adminUserId == null) {
                try (PreparedStatement psAdmin = conn.prepareStatement(
                        "SELECT id FROM users WHERE role = 'administrador' AND estado = 1 ORDER BY id ASC LIMIT 1")) {
                    try (ResultSet rsAdmin = psAdmin.executeQuery()) {
                        if (rsAdmin.next()) {
                            adminUserId = rsAdmin.getInt("id");
                        }
                    }
                } catch (Exception e) {
                    System.err.println("Error buscando admin fallback: " + e.getMessage());
                }
            }

            String sql = "INSERT INTO users (dni, nombre, apellidos, email, password, role, estado, usercrea, usermod) VALUES (?,?,?,?,?,?,1,?,?)";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, dni);
                ps.setString(2, nombre);
                ps.setString(3, apellidos);
                ps.setString(4, email);
                ps.setString(5, hash);
                ps.setString(6, role);

                // Si no se puede obtener el admin, usar NULL
                if (adminUserId != null) {
                    ps.setInt(7, adminUserId); // usercrea
                    ps.setInt(8, adminUserId); // usermod
                } else {
                    ps.setNull(7, Types.INTEGER);
                    ps.setNull(8, Types.INTEGER);
                }

                ps.executeUpdate();
            }
            resp.getWriter().write("{\"success\":true,\"message\":\"Usuario creado\"}");
        } catch (SQLException e) {
            System.err.println("[UsersServlet] Database error creating user: " + e.getMessage());
            e.printStackTrace();
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"Error de base de datos: "
                    + e.getMessage().replace("\"", "\\\"") + "\"}");
        } catch (Exception e) {
            System.err.println("[UsersServlet] Unexpected error creating user: " + e.getMessage());
            e.printStackTrace();
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"Error inesperado: "
                    + e.getMessage().replace("\"", "\\\"") + "\"}");
        }
    }
}