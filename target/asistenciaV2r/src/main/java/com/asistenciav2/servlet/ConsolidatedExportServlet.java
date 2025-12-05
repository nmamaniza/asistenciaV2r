package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.YearMonth;

@WebServlet("/api/consolidated-export")
public class ConsolidatedExportServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String anioStr = req.getParameter("anio");
        String mesStr = req.getParameter("mes");
        int anio = (anioStr != null && !anioStr.isEmpty()) ? Integer.parseInt(anioStr)
                : java.time.LocalDate.now().getYear();
        int mes = (mesStr != null && !mesStr.isEmpty()) ? Integer.parseInt(mesStr)
                : java.time.LocalDate.now().getMonthValue();
        int days = YearMonth.of(anio, mes).lengthOfMonth();

        resp.setContentType("text/csv; charset=UTF-8");
        resp.setHeader("Content-Disposition",
                "attachment; filename=consolidado_" + anio + "_" + String.format("%02d", mes) + ".csv");
        try (PrintWriter out = resp.getWriter(); Connection conn = DatabaseConnection.getConnection()) {
            // Header
            StringBuilder header = new StringBuilder("dni,nombre,modalidad,cargo,area");
            for (int d = 1; d <= days; d++)
                header.append(",d" + String.format("%02d", d));
            out.println(header);

            String sql = "SELECT u.dni, COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre, " +
                    "ja.modalidad, ja.cargo, ja.area, ja.id as job_id, da.fecha, da.final " +
                    "FROM jobassignments ja JOIN users u ON u.id = ja.user_id " +
                    "LEFT JOIN dailyattendances da ON da.jobassignment_id = ja.id " +
                    "AND EXTRACT(YEAR FROM da.fecha) = ? AND EXTRACT(MONTH FROM da.fecha) = ? AND da.estado = 1 " +
                    "WHERE ja.estado = 1 " +
                    "ORDER BY u.dni ASC, ja.id ASC, da.fecha ASC";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setInt(1, anio);
                ps.setInt(2, mes);
                ResultSet rs = ps.executeQuery();

                String currentKey = null;
                String currentDni = null;
                String nombre = null;
                String modalidad = null;
                String cargo = null;
                String area = null;
                String[] cols = new String[days];

                while (rs.next()) {
                    String dni = rs.getString("dni");
                    long jobId = rs.getLong("job_id");
                    String key = dni + "_" + jobId;

                    if (!key.equals(currentKey) && currentKey != null) {
                        // flush previous row
                        out.print(currentDni + "," + escape(nombre) + "," + escape(modalidad) + "," + escape(cargo)
                                + "," + escape(area));
                        for (int d = 0; d < days; d++)
                            out.print("," + escape(cols[d]));
                        out.println();
                        cols = new String[days];
                    }
                    currentKey = key;
                    currentDni = dni;
                    nombre = rs.getString("nombre");
                    modalidad = rs.getString("modalidad");
                    cargo = rs.getString("cargo");
                    area = rs.getString("area");

                    java.sql.Date f = rs.getDate("fecha");
                    if (f != null) {
                        int day = f.toLocalDate().getDayOfMonth();
                        if (day >= 1 && day <= days) {
                            cols[day - 1] = rs.getString("final");
                        }
                    }
                }
                if (currentKey != null) {
                    out.print(currentDni + "," + escape(nombre) + "," + escape(modalidad) + "," + escape(cargo) + ","
                            + escape(area));
                    for (int d = 0; d < days; d++)
                        out.print("," + escape(cols[d]));
                    out.println();
                }
            }
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        }
    }

    private String escape(String v) {
        if (v == null)
            return "";
        String s = v.replace("\"", "\"\"");
        if (s.indexOf(',') >= 0)
            return '"' + s + '"';
        return s;
    }
}