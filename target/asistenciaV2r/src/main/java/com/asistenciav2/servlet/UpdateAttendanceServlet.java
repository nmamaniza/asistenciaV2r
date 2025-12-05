package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;

public class UpdateAttendanceServlet extends HttpServlet {
    
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        String idStr = request.getParameter("id");
        String doc = request.getParameter("doc");
        String finalValue = request.getParameter("final");
        
        try {
            int id = Integer.parseInt(idStr);
            
            try (Connection conn = DatabaseConnection.getConnection()) {
                String sql = "UPDATE daily_attendance SET doc = ?, final = ? WHERE id = ?";
                PreparedStatement stmt = conn.prepareStatement(sql);
                stmt.setString(1, doc);
                stmt.setString(2, finalValue);
                stmt.setInt(3, id);
                
                int rowsUpdated = stmt.executeUpdate();
                
                PrintWriter out = response.getWriter();
                if (rowsUpdated > 0) {
                    out.print("{\"success\": true, \"message\": \"Registro actualizado correctamente\"}");
                } else {
                    out.print("{\"success\": false, \"message\": \"No se encontró el registro\"}");
                }
                out.flush();
                
            } catch (SQLException e) {
                e.printStackTrace();
                response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
                PrintWriter out = response.getWriter();
                out.print("{\"success\": false, \"message\": \"Error de base de datos\"}");
                out.flush();
            }
            
        } catch (NumberFormatException e) {
            response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            PrintWriter out = response.getWriter();
            out.print("{\"success\": false, \"message\": \"ID inválido\"}");
            out.flush();
        }
    }
}