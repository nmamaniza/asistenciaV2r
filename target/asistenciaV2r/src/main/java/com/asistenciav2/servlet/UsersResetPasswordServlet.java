package com.asistenciav2.servlet;

import com.asistenciav2.util.BCryptUtil;
import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;

@WebServlet("/api/users/reset-password")
public class UsersResetPasswordServlet extends HttpServlet {
    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String idStr = req.getParameter("id");
        String newPassword = req.getParameter("password");
        try (Connection conn = DatabaseConnection.getConnection()) {
            String hash = BCryptUtil.hashPassword(newPassword);
            String sql = "UPDATE users SET password=? WHERE id=?";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, hash);
                ps.setInt(2, Integer.parseInt(idStr));
                ps.executeUpdate();
            }
            resp.getWriter().write("{\"success\":true,\"message\":\"Contraseña actualizada\"}");
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"Error actualizando contraseña\"}");
        }
    }
}