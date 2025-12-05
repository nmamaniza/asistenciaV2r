package com.asistenciav2.servlet;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;

@WebServlet("/api/test-connection")
public class TestConnectionServlet extends HttpServlet {
    
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        
        System.out.println("[TestConnectionServlet] Iniciando prueba de conexión...");
        
        try {
            // Probar conexión
            try (Connection conn = DatabaseConnection.getConnection()) {
                System.out.println("[TestConnectionServlet] Conexión establecida exitosamente");
                
                // Probar consulta simple
                String sql = "SELECT COUNT(*) as total FROM users";
                try (PreparedStatement ps = conn.prepareStatement(sql)) {
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            int total = rs.getInt("total");
                            System.out.println("[TestConnectionServlet] Total de usuarios: " + total);
                            
                            // Respuesta exitosa
                            String json = "{\"success\":true,\"message\":\"Conexión exitosa\",\"total_users\":" + total + "}";
                            resp.getWriter().write(json);
                            return;
                        }
                    }
                }
                
                // Si no hay resultados
                String json = "{\"success\":true,\"message\":\"Conexión exitosa pero no hay usuarios\",\"total_users\":0}";
                resp.getWriter().write(json);
                
            } catch (Exception e) {
                System.err.println("[TestConnectionServlet] Error de conexión: " + e.getMessage());
                e.printStackTrace();
                
                String json = "{\"success\":false,\"message\":\"Error de conexión: " + e.getMessage().replace("\"", "\\\"") + "\"}";
                resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
                resp.getWriter().write(json);
            }
            
        } catch (Exception e) {
            System.err.println("[TestConnectionServlet] Error inesperado: " + e.getMessage());
            e.printStackTrace();
            
            String json = "{\"success\":false,\"message\":\"Error inesperado: " + e.getMessage().replace("\"", "\\\"") + "\"}";
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write(json);
        }
    }
}