package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.*;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import com.fasterxml.jackson.databind.ObjectMapper;

@WebServlet("/api/punch-events")
public class PunchEventsServlet extends HttpServlet {
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.setHeader("Access-Control-Allow-Origin", "*");
        response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        response.setHeader("Access-Control-Allow-Headers", "Content-Type");
        
        List<Map<String, Object>> punchEventsList = new ArrayList<>();
        
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT id, dni, nombre, fechahora, fecha, hora, clock_id, estado " +
                        "FROM punch_events " +
                        "ORDER BY fechahora DESC LIMIT 50";
            
            PreparedStatement stmt = conn.prepareStatement(sql);
            ResultSet rs = stmt.executeQuery();
            
            while (rs.next()) {
                Map<String, Object> punchEvent = new HashMap<>();
                punchEvent.put("id", rs.getInt("id"));
                punchEvent.put("dni", rs.getString("dni"));
                punchEvent.put("nombre", rs.getString("nombre"));
                punchEvent.put("fechahora", rs.getTimestamp("fechahora").toString());
                punchEvent.put("fecha", rs.getDate("fecha").toString());
                punchEvent.put("hora", rs.getTime("hora").toString());
                punchEvent.put("clock_id", rs.getString("clock_id"));
                punchEvent.put("estado", rs.getString("estado"));
                
                punchEventsList.add(punchEvent);
            }
            
        } catch (SQLException e) {
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            Map<String, String> error = new HashMap<>();
            error.put("error", "Error de base de datos: " + e.getMessage());
            
            ObjectMapper mapper = new ObjectMapper();
            PrintWriter out = response.getWriter();
            out.print(mapper.writeValueAsString(error));
            out.flush();
            return;
        }
        
        ObjectMapper mapper = new ObjectMapper();
        PrintWriter out = response.getWriter();
        out.print(mapper.writeValueAsString(punchEventsList));
        out.flush();
    }
    
    @Override
    protected void doOptions(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setHeader("Access-Control-Allow-Origin", "*");
        response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        response.setHeader("Access-Control-Allow-Headers", "Content-Type");
        response.setStatus(HttpServletResponse.SC_OK);
    }
}