package com.asistenciav2.servlet;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import com.asistenciav2.util.DatabaseConnection;

import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

@WebServlet("/api/userInfo")
public class UserInfoServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() ||
                "anonymousUser".equals(authentication.getPrincipal())) {
            // No autenticado: responder con éxito=false para que el frontend use valores
            // por defecto
            writeJson(response, "{\"success\":false}");
            return;
        }

        String username = authentication.getName();
        String displayName = getUserNameFromDatabase(username);
        String apellidos = getUserSurnamesFromDatabase(username);
        Integer userId = getUserIdFromDatabase(username);
        if (displayName == null || displayName.trim().isEmpty()) {
            displayName = username;
        }

        boolean isAdmin = authentication.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"));

        String json = String.format("{\"success\":true,\"id\":%d,\"nombre\":\"%s\",\"apellidos\":\"%s\",\"isAdmin\":%b}",
                userId, escapeJson(displayName), escapeJson(apellidos), isAdmin);
        writeJson(response, json);
    }

    private Integer getUserIdFromDatabase(String username) {
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT id FROM users WHERE (email = ? OR dni = ?) AND estado = 1";
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, username);
                stmt.setString(2, username);
                try (ResultSet rs = stmt.executeQuery()) {
                    if (rs.next()) {
                        return rs.getInt(1);
                    }
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return null;
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        doGet(request, response);
    }

    private void writeJson(HttpServletResponse response, String json) throws IOException {
        PrintWriter out = response.getWriter();
        out.print(json);
        out.flush();
    }

    private String getUserNameFromDatabase(String username) {
        try (Connection conn = DatabaseConnection.getConnection()) {
            // Intentar obtener el nombre desde la tabla users usando email o dni
            String sql = "SELECT nombre FROM users WHERE (email = ? OR dni = ?) AND estado = 1";
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, username);
                stmt.setString(2, username);
                try (ResultSet rs = stmt.executeQuery()) {
                    if (rs.next()) {
                        return rs.getString(1);
                    }
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return null;
    }

    private String getUserSurnamesFromDatabase(String username) {
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT apellidos FROM users WHERE (email = ? OR dni = ?) AND estado = 1";
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, username);
                stmt.setString(2, username);
                try (ResultSet rs = stmt.executeQuery()) {
                    if (rs.next()) {
                        return rs.getString(1);
                    }
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return null;
    }

    private String escapeJson(String text) {
        if (text == null)
            return "";
        return text.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
