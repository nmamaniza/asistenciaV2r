package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.http.*;
import jakarta.servlet.annotation.WebServlet;
import java.io.IOException;
import java.io.PrintWriter;
import java.sql.*;

@WebServlet("/api/processed-update")
public class UpdateDailyAttendanceServlet extends HttpServlet {
    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String idStr = req.getParameter("id");
        String doc = req.getParameter("doc");
        String finalValue = req.getParameter("final");
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "UPDATE dailyattendances SET doc = ?, final = ? WHERE id = ? AND estado = 1";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, doc);
                ps.setString(2, finalValue);
                ps.setInt(3, Integer.parseInt(idStr));
                int updated = ps.executeUpdate();
                PrintWriter out = resp.getWriter();
                if (updated > 0) {
                    out.write("{\"success\":true,\"message\":\"Actualizado\"}");
                } else {
                    out.write("{\"success\":false,\"message\":\"No actualizado\"}");
                }
                out.flush();
            }
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"Error de servidor\"}");
        }
    }
}