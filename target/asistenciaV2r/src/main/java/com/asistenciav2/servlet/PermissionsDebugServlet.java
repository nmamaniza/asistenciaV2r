package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.io.PrintWriter;
import java.sql.*;

@WebServlet("/api/permissions-debug")
public class PermissionsDebugServlet extends HttpServlet {
    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        PrintWriter out = resp.getWriter();
        
        try {
            // Get parameters
            String userIdStr = req.getParameter("userId");
            String permissionTypeCode = req.getParameter("permissionType");
            String fechainiStr = req.getParameter("fechaini");
            String fechafinStr = req.getParameter("fechafin");
            String jobIdStr = req.getParameter("jobassignmentId");
            
            System.out.println("=== PERMISSIONS DEBUG ===");
            System.out.println("userId: " + userIdStr);
            System.out.println("permissionType: " + permissionTypeCode);
            System.out.println("fechaini: " + fechainiStr);
            System.out.println("fechafin: " + fechafinStr);
            System.out.println("jobassignmentId: " + jobIdStr);
            
            // Check if dates look like timestamps
            if (fechainiStr != null && fechainiStr.matches("\\d{10,13}")) {
                System.out.println("WARNING: fechaini looks like a timestamp: " + fechainiStr);
            }
            if (fechafinStr != null && fechafinStr.matches("\\d{10,13}")) {
                System.out.println("WARNING: fechafin looks like a timestamp: " + fechafinStr);
            }
            
            // Validate parameters
            if (fechainiStr == null || fechainiStr.isEmpty()) {
                throw new Exception("La fecha de inicio es requerida");
            }
            if (permissionTypeCode == null || permissionTypeCode.isEmpty()) {
                throw new Exception("El tipo de permiso es requerido");
            }
            
            try (Connection conn = DatabaseConnection.getConnection()) {
                System.out.println("Database connection successful");
                
                // Get user ID
                Integer userId;
                if (userIdStr != null && !userIdStr.isEmpty()) {
                    userId = Integer.parseInt(userIdStr);
                    System.out.println("User ID: " + userId);
                } else {
                    throw new Exception("User ID is required");
                }
                
                // Get permission type
                Integer typeId = null;
                System.out.println("Looking up permission type: " + permissionTypeCode);
                try (PreparedStatement ps = conn.prepareStatement("SELECT id FROM permissiontypes WHERE codigo = ? AND estado = 1")) {
                    ps.setString(1, permissionTypeCode);
                    ResultSet rs = ps.executeQuery();
                    if (rs.next()) typeId = rs.getInt(1);
                }
                
                if (typeId == null) {
                    throw new Exception("Tipo de permiso invalido: " + permissionTypeCode);
                }
                System.out.println("Permission type ID: " + typeId);
                
                // Parse dates
                java.sql.Date fechaini = null;
                java.sql.Date fechafin = null;
                
                try {
                    fechaini = java.sql.Date.valueOf(fechainiStr);
                } catch (IllegalArgumentException e) {
                    try {
                        long timestamp = Long.parseLong(fechainiStr);
                        if (timestamp > 9999999999L) {
                            timestamp = timestamp / 1000;
                        }
                        fechaini = new java.sql.Date(timestamp * 1000);
                    } catch (NumberFormatException e2) {
                        throw new Exception("Formato de fecha invalido para fechaini: " + fechainiStr);
                    }
                }
                
                if (fechafinStr != null && !fechafinStr.isEmpty()) {
                    try {
                        fechafin = java.sql.Date.valueOf(fechafinStr);
                    } catch (IllegalArgumentException e) {
                        try {
                            long timestamp = Long.parseLong(fechafinStr);
                            if (timestamp > 9999999999L) {
                                timestamp = timestamp / 1000;
                            }
                            fechafin = new java.sql.Date(timestamp * 1000);
                        } catch (NumberFormatException e2) {
                            throw new Exception("Formato de fecha invalido para fechafin: " + fechafinStr);
                        }
                    }
                }
                Integer jobId = (jobIdStr != null && !jobIdStr.isEmpty()) ? Integer.parseInt(jobIdStr) : null;
                
                System.out.println("Dates parsed: fechaini=" + fechaini + ", fechafin=" + fechafin + ", jobId=" + jobId);
                
                // Test INSERT
                String sql = "INSERT INTO permissions (permissiontype_id, fechaini, fechafin, user_id, jobassignment_id, estado) VALUES (?,?,?,?,?,1)";
                try (PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
                    ps.setInt(1, typeId);
                    ps.setDate(2, fechaini);
                    if (fechafin == null) ps.setNull(3, java.sql.Types.DATE); else ps.setDate(3, fechafin);
                    ps.setInt(4, userId);
                    if (jobId == null) ps.setNull(5, java.sql.Types.INTEGER); else ps.setInt(5, jobId);
                    
                    System.out.println("Executing INSERT...");
                    int rowsAffected = ps.executeUpdate();
                    System.out.println("Rows affected: " + rowsAffected);
                    
                    int newId = -1;
                    try (ResultSet gk = ps.getGeneratedKeys()) {
                        if (gk.next()) {
                            newId = gk.getInt(1);
                            System.out.println("Generated ID: " + newId);
                        }
                    }
                    
                    out.write("{\"success\":true,\"message\":\"Permission created successfully\",\"id\":" + newId + "}");
                }
                
            }
            
        } catch (Exception e) {
            System.err.println("ERROR in PermissionsDebugServlet: " + e.getMessage());
            e.printStackTrace();
            out.write("{\"success\":false,\"message\":\"Error: " + e.getClass().getSimpleName() + "\"}");
        }
    }
    
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("text/html");
        PrintWriter out = resp.getWriter();
        
        out.println("<!DOCTYPE html>");
        out.println("<html><head><title>Permissions Debug Test</title></head><body>");
        out.println("<h1>Permissions Debug Test</h1>");
        out.println("<form method='POST'>");
        out.println("User ID: <input type='text' name='userId' value='1'><br>");
        out.println("Permission Type: <input type='text' name='permissionType' value='VACACIONES'><br>");
        out.println("Fecha Inicio: <input type='text' name='fechaini' value='2024-01-01'><br>");
        out.println("Fecha Fin: <input type='text' name='fechafin' value='2024-01-31'><br>");
        out.println("Job Assignment ID: <input type='text' name='jobassignmentId'><br>");
        out.println("<input type='submit' value='Test Permission Creation'>");
        out.println("</form>");
        out.println("</body></html>");
    }
}