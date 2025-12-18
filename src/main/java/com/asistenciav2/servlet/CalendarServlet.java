package com.asistenciav2.servlet;

import com.google.gson.Gson;
import com.google.gson.JsonObject;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.BufferedReader;
import java.io.IOException;
import java.sql.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

// Importar DatabaseConnection
import com.asistenciav2.util.DatabaseConnection;

/**
 * Servlet para gestionar el calendario laboral
 * GET: Obtener días del calendario por año y mes
 * PUT: Actualizar el estado de un día específico
 * POST: Generar calendario para un año nuevo
 */
@WebServlet("/api/calendar")
public class CalendarServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        // Spring Security ya maneja la autenticación

        String op = request.getParameter("op");
        if ("years".equals(op)) {
            try (Connection conn = DatabaseConnection.getConnection()) {
                String sql = "SELECT DISTINCT EXTRACT(YEAR FROM fecha) as year FROM calendardays ORDER BY year DESC";
                try (PreparedStatement stmt = conn.prepareStatement(sql);
                        ResultSet rs = stmt.executeQuery()) {

                    List<Integer> years = new ArrayList<>();
                    while (rs.next()) {
                        years.add(rs.getInt("year"));
                    }

                    Gson gson = new Gson();
                    response.getWriter().write(gson.toJson(years));
                    return;
                }
            } catch (SQLException e) {
                e.printStackTrace();
                response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
                response.getWriter().write("{\"error\":\"Error al obtener años disponibles: " + e.getMessage() + "\"}");
                return;
            }
        }

        String year = request.getParameter("year");
        String month = request.getParameter("month");

        if (year == null) {
            response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            response.getWriter().write("{\"error\":\"Año requerido\"}");
            return;
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            List<Map<String, Object>> calendarDays = new ArrayList<>();

            String sql;
            PreparedStatement stmt;

            if (month != null) {
                // Obtener días de un mes específico
                sql = "SELECT id, fecha, estado, descripcion, es_feriado_nacional " +
                        "FROM calendardays " +
                        "WHERE EXTRACT(YEAR FROM fecha) = ? AND EXTRACT(MONTH FROM fecha) = ? " +
                        "ORDER BY fecha";
                stmt = conn.prepareStatement(sql);
                stmt.setInt(1, Integer.parseInt(year));
                stmt.setInt(2, Integer.parseInt(month));
            } else {
                // Obtener todos los días del año
                sql = "SELECT id, fecha, estado, descripcion, es_feriado_nacional " +
                        "FROM calendardays " +
                        "WHERE EXTRACT(YEAR FROM fecha) = ? " +
                        "ORDER BY fecha";
                stmt = conn.prepareStatement(sql);
                stmt.setInt(1, Integer.parseInt(year));
            }

            ResultSet rs = stmt.executeQuery();

            while (rs.next()) {
                Map<String, Object> day = new HashMap<>();
                day.put("id", rs.getInt("id"));
                day.put("fecha", rs.getDate("fecha").toString());
                day.put("estado", rs.getInt("estado"));
                day.put("descripcion", rs.getString("descripcion"));
                day.put("esFeriadoNacional", rs.getBoolean("es_feriado_nacional"));
                calendarDays.add(day);
            }

            Gson gson = new Gson();
            String json = gson.toJson(calendarDays);
            response.getWriter().write(json);

        } catch (SQLException e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"error\":\"Error al obtener calendario: " + e.getMessage() + "\"}");
        }
    }

    @Override
    protected void doPut(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        // Spring Security ya verificado

        // Leer datos del request
        StringBuilder sb = new StringBuilder();
        try (BufferedReader reader = request.getReader()) {
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
        }

        Gson gson = new Gson();
        JsonObject jsonObject = gson.fromJson(sb.toString(), JsonObject.class);

        String fecha = jsonObject.has("fecha") ? jsonObject.get("fecha").getAsString() : null;
        Integer estado = jsonObject.has("estado") ? jsonObject.get("estado").getAsInt() : null;
        String descripcion = jsonObject.has("descripcion") ? jsonObject.get("descripcion").getAsString() : null;

        if (fecha == null || estado == null) {
            response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            response.getWriter().write("{\"error\":\"Fecha y estado son requeridos\"}");
            return;
        }

        // Validar estado (0=no laborable, 1=laborable, 2=recuperable)
        if (estado < 0 || estado > 2) {
            response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            response.getWriter()
                    .write("{\"error\":\"Estado inválido. Debe ser 0 (no laborable), 1 (laborable) o 2 (recuperable)\"}");
            return;
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            // Obtener userId
            Integer userId = null;
            String username = request.getRemoteUser();
            if (username != null) {
                String userSql = "SELECT id FROM users WHERE email = ? OR dni = ? LIMIT 1";
                try (PreparedStatement userStmt = conn.prepareStatement(userSql)) {
                    userStmt.setString(1, username);
                    userStmt.setString(2, username);
                    try (ResultSet rs = userStmt.executeQuery()) {
                        if (rs.next()) {
                            userId = rs.getInt("id");
                        }
                    }
                }
            }

            String sql = "UPDATE calendardays SET estado = ?, descripcion = ?, usermod = ?, updated_at = CURRENT_TIMESTAMP "
                    +
                    "WHERE fecha = ?";
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setInt(1, estado);
                if (descripcion != null) {
                    stmt.setString(2, descripcion);
                } else {
                    stmt.setNull(2, java.sql.Types.VARCHAR);
                }

                if (userId != null) {
                    stmt.setInt(3, userId);
                } else {
                    stmt.setNull(3, java.sql.Types.INTEGER);
                }
                stmt.setDate(4, Date.valueOf(fecha));

                int rowsAffected = stmt.executeUpdate();

                if (rowsAffected > 0) {
                    Map<String, Object> result = new HashMap<>();
                    result.put("success", true);
                    result.put("message", "Calendario actualizado correctamente");
                    result.put("fecha", fecha);
                    result.put("estado", estado);
                    response.getWriter().write(gson.toJson(result));
                } else {
                    response.setStatus(HttpServletResponse.SC_NOT_FOUND);
                    response.getWriter().write("{\"error\":\"Fecha no encontrada en el calendario\"}");
                }
            }

        } catch (SQLException e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"error\":\"Error al actualizar calendario: " + e.getMessage() + "\"}");
        }
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        // Spring Security ya verificó que el usuario es ADMIN

        // Leer datos del request
        StringBuilder sb = new StringBuilder();
        try (BufferedReader reader = request.getReader()) {
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
        }

        Gson gson = new Gson();
        JsonObject jsonObject = gson.fromJson(sb.toString(), JsonObject.class);

        String yearStr = jsonObject.has("year") ? jsonObject.get("year").getAsString() : null;

        if (yearStr == null) {
            response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            response.getWriter().write("{\"error\":\"Año requerido\"}");
            return;
        }

        int year;
        try {
            year = Integer.parseInt(yearStr);
        } catch (NumberFormatException e) {
            response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            response.getWriter().write("{\"error\":\"Año inválido\"}");
            return;
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            // 1. Verificar si el año ya existe
            String checkSql = "SELECT COUNT(*) FROM calendardays WHERE EXTRACT(YEAR FROM fecha) = ?";
            try (PreparedStatement checkStmt = conn.prepareStatement(checkSql)) {
                checkStmt.setInt(1, year);
                try (ResultSet rs = checkStmt.executeQuery()) {
                    if (rs.next() && rs.getInt(1) > 0) {
                        response.setStatus(HttpServletResponse.SC_BAD_REQUEST); // O Conflict 409
                        response.getWriter().write("{\"error\":\"El calendario para el año " + year
                                + " ya existe y no puede ser sobrescrito.\"}");
                        return;
                    }
                }
            }

            // 2. Generar días
            conn.setAutoCommit(false); // Iniciar transacción
            try {
                String insertSql = "INSERT INTO calendardays (fecha, estado, descripcion, es_feriado_nacional, created_at, updated_at) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)";
                try (PreparedStatement insertStmt = conn.prepareStatement(insertSql)) {

                    java.time.LocalDate startDate = java.time.LocalDate.of(year, 1, 1);
                    java.time.LocalDate endDate = java.time.LocalDate.of(year, 12, 31);

                    // Calcular feriados movibles (Semana Santa)
                    java.time.LocalDate easterSunday = getEasterSunday(year);
                    java.time.LocalDate goodFriday = easterSunday.minusDays(2);
                    java.time.LocalDate maundyThursday = easterSunday.minusDays(3);

                    for (java.time.LocalDate date = startDate; !date.isAfter(endDate); date = date.plusDays(1)) {
                        int estado = 1; // 1: Laborable por defecto
                        String descripcion = "Laborable";
                        boolean esFeriadoNacional = false;

                        // Verificar feriados fijos
                        if (isFixedHoliday(date)) {
                            estado = 0; // 0: No Laborable / Feriado
                            descripcion = getFixedHolidayName(date);
                            esFeriadoNacional = true;
                        }
                        // Verificar feriados movibles
                        else if (date.equals(goodFriday)) {
                            estado = 0;
                            descripcion = "Viernes Santo";
                            esFeriadoNacional = true;
                        } else if (date.equals(maundyThursday)) {
                            estado = 0;
                            descripcion = "Jueves Santo";
                            esFeriadoNacional = true;
                        }
                        // Domingos y Sábados
                        else if (date.getDayOfWeek() == java.time.DayOfWeek.SUNDAY) {
                            estado = 0;
                            descripcion = "Domingo";
                            esFeriadoNacional = false;
                        } else if (date.getDayOfWeek() == java.time.DayOfWeek.SATURDAY) {
                            estado = 0;
                            descripcion = "Sábado";
                            esFeriadoNacional = false;
                        }

                        insertStmt.setDate(1, java.sql.Date.valueOf(date));
                        insertStmt.setInt(2, estado);
                        insertStmt.setString(3, descripcion);
                        insertStmt.setBoolean(4, esFeriadoNacional);
                        insertStmt.addBatch();
                    }
                    insertStmt.executeBatch();
                }
                conn.commit(); // Confirmar transacción

                Map<String, Object> result = new HashMap<>();
                result.put("success", true);
                result.put("message", "Calendario " + year + " generado correctamente con feriados de Perú.");
                response.getWriter().write(gson.toJson(result));

            } catch (SQLException e) {
                conn.rollback();
                throw e;
            } finally {
                conn.setAutoCommit(true);
            }

        } catch (SQLException e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"error\":\"Error al generar calendario: " + e.getMessage() + "\"}");
        }
    }

    // Algoritmo de Gauss para calcular Domingo de Pascua
    private java.time.LocalDate getEasterSunday(int year) {
        int a = year % 19;
        int b = year / 100;
        int c = year % 100;
        int d = b / 4;
        int e = b % 4;
        int f = (b + 8) / 25;
        int g = (b - f + 1) / 3;
        int h = (19 * a + b - d - g + 15) % 30;
        int i = c / 4;
        int k = c % 4;
        int l = (32 + 2 * e + 2 * i - h - k) % 7;
        int m = (a + 11 * h + 22 * l) / 451;
        int month = (h + l - 7 * m + 114) / 31;
        int day = ((h + l - 7 * m + 114) % 31) + 1;
        return java.time.LocalDate.of(year, month, day);
    }

    private boolean isFixedHoliday(java.time.LocalDate date) {
        int d = date.getDayOfMonth();
        int m = date.getMonthValue();

        return (d == 1 && m == 1) || // Año Nuevo
                (d == 1 && m == 5) || // Día del Trabajo
                (d == 7 && m == 6) || // Batalla de Arica y Día de la Bandera
                (d == 29 && m == 6) || // San Pedro y San Pablo
                (d == 23 && m == 7) || // Día de la Fuerza Aérea
                (d == 28 && m == 7) || // Fiestas Patrias
                (d == 29 && m == 7) || // Fiestas Patrias
                (d == 6 && m == 8) || // Batalla de Junín
                (d == 30 && m == 8) || // Santa Rosa de Lima
                (d == 8 && m == 10) || // Combate de Angamos
                (d == 1 && m == 11) || // Todos los Santos
                (d == 8 && m == 12) || // Inmaculada Concepción
                (d == 9 && m == 12) || // Batalla de Ayacucho
                (d == 25 && m == 12); // Navidad
    }

    private String getFixedHolidayName(java.time.LocalDate date) {
        int d = date.getDayOfMonth();
        int m = date.getMonthValue();
        if (d == 1 && m == 1)
            return "Año Nuevo";
        if (d == 1 && m == 5)
            return "Día del Trabajo";
        if (d == 7 && m == 6)
            return "Batalla de Arica y Día de la Bandera";
        if (d == 29 && m == 6)
            return "San Pedro y San Pablo";
        if (d == 23 && m == 7)
            return "Día de la Fuerza Aérea del Perú";
        if (d == 28 && m == 7)
            return "Fiestas Patrias";
        if (d == 29 && m == 7)
            return "Fiestas Patrias";
        if (d == 6 && m == 8)
            return "Batalla de Junín";
        if (d == 30 && m == 8)
            return "Santa Rosa de Lima";
        if (d == 8 && m == 10)
            return "Combate de Angamos";
        if (d == 1 && m == 11)
            return "Día de Todos los Santos";
        if (d == 8 && m == 12)
            return "Inmaculada Concepción";
        if (d == 9 && m == 12)
            return "Batalla de Ayacucho";
        if (d == 25 && m == 12)
            return "Navidad";
        return "Feriado";
    }
}
