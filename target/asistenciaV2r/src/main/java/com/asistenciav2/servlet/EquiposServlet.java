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

@WebServlet("/api/equipos")
public class EquiposServlet extends HttpServlet {
    
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json; charset=UTF-8");
        
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT DISTINCT equipo FROM jobassignments WHERE equipo IS NOT NULL AND equipo != '' ORDER BY equipo ASC";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ResultSet rs = ps.executeQuery();
                List<String> equipos = new ArrayList<>();
                while (rs.next()) {
                    equipos.add(rs.getString("equipo"));
                }
                
                String json = new com.fasterxml.jackson.databind.ObjectMapper()
                    .writeValueAsString(equipos);
                resp.getWriter().write(json);
            }
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("[]");
            e.printStackTrace();
        }
    }
}