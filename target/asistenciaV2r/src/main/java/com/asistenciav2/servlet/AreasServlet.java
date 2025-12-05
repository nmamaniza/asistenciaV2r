package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

@WebServlet("/api/areas")
public class AreasServlet extends HttpServlet {
    
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json; charset=UTF-8");
        
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT DISTINCT area FROM jobassignments WHERE area IS NOT NULL AND area != '' ORDER BY area ASC";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ResultSet rs = ps.executeQuery();
                List<String> areas = new ArrayList<>();
                while (rs.next()) {
                    areas.add(rs.getString("area"));
                }
                
                String json = new com.fasterxml.jackson.databind.ObjectMapper()
                    .writeValueAsString(areas);
                resp.getWriter().write(json);
            }
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("[]");
            e.printStackTrace();
        }
    }
}