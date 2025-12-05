package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.*;

@WebServlet("/api/permission-types")
public class PermissionTypesServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        List<Map<String, Object>> out = new ArrayList<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT id, codigo, descripcion, permite_doble_cargo, requiere_programacion, minutos_diarios_default, dias_maximo, estado FROM permissiontypes WHERE estado=1 ORDER BY codigo";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    row.put("id", rs.getInt("id"));
                    row.put("codigo", rs.getString("codigo"));
                    row.put("descripcion", rs.getString("descripcion"));
                    row.put("permite_doble_cargo", rs.getBoolean("permite_doble_cargo"));
                    row.put("requiere_programacion", rs.getBoolean("requiere_programacion"));
                    row.put("minutos_diarios_default", rs.getObject("minutos_diarios_default"));
                    row.put("dias_maximo", rs.getObject("dias_maximo"));
                    out.add(row);
                }
            }
        } catch (SQLException e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        }
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }
}