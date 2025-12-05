package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.*;
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

public class AttendanceDataServlet extends HttpServlet {
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        List<Map<String, Object>> attendanceList = new ArrayList<>();
        
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT id, job_assignment_id, fecha, anio, mes, horaini, " +
                        "horafin, horaint, nummarca, obs, mintarde, retarde, " +
                        "flaglab, horaslab, minlab, doc, final FROM daily_attendance ORDER BY fecha DESC";
            
            PreparedStatement stmt = conn.prepareStatement(sql);
            ResultSet rs = stmt.executeQuery();
            
            while (rs.next()) {
                Map<String, Object> attendance = new HashMap<>();
                attendance.put("id", rs.getInt("id"));
                attendance.put("job_assignment_id", rs.getInt("job_assignment_id"));
                attendance.put("fecha", rs.getDate("fecha"));
                attendance.put("anio", rs.getInt("anio"));
                attendance.put("mes", rs.getInt("mes"));
                attendance.put("horaini", rs.getTime("horaini"));
                attendance.put("horafin", rs.getTime("horafin"));
                attendance.put("horaint", rs.getTime("horaint"));
                attendance.put("nummarca", rs.getInt("nummarca"));
                attendance.put("obs", rs.getString("obs"));
                attendance.put("mintarde", rs.getInt("mintarde"));
                attendance.put("retarde", rs.getInt("retarde"));
                attendance.put("flaglab", rs.getBoolean("flaglab"));
                attendance.put("horaslab", rs.getInt("horaslab"));
                attendance.put("minlab", rs.getInt("minlab"));
                attendance.put("doc", rs.getString("doc"));
                attendance.put("final", rs.getString("final"));
                
                attendanceList.add(attendance);
            }
            
        } catch (SQLException e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            return;
        }
        
        ObjectMapper mapper = new ObjectMapper();
        PrintWriter out = response.getWriter();
        out.print(mapper.writeValueAsString(attendanceList));
        out.flush();
    }
}