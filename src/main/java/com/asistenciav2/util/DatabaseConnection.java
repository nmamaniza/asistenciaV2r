package com.asistenciav2.util;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import javax.sql.DataSource;
import org.postgresql.ds.PGSimpleDataSource;

public class DatabaseConnection {
    // Valores por defecto (se usarán si no hay variables de entorno)
    private static final String DEFAULT_URL = "jdbc:postgresql://localhost:5432/asistenciaV2r";
    private static final String DEFAULT_USERNAME = "nestor";
    private static final String DEFAULT_PASSWORD = "Arequipa@2018";

    // Permitir configurar vía variables de entorno sin tocar el código
    // DB_URL, DB_USER, DB_PASSWORD
    private static final String URL = getEnvOrDefault("DB_URL", DEFAULT_URL);
    private static final String USERNAME = getEnvOrDefault("DB_USER", DEFAULT_USERNAME);
    private static final String PASSWORD = getEnvOrDefault("DB_PASSWORD", DEFAULT_PASSWORD);

    private static String getEnvOrDefault(String key, String defaultValue) {
        String value = System.getenv(key);
        return (value != null && !value.isEmpty()) ? value : defaultValue;
    }
    
    static {
        try {
            Class.forName("org.postgresql.Driver");
        } catch (ClassNotFoundException e) {
            throw new RuntimeException("PostgreSQL Driver not found", e);
        }
    }
    
    public static Connection getConnection() throws SQLException {
        return DriverManager.getConnection(URL, USERNAME, PASSWORD);
    }
    
    public static DataSource getDataSource() throws SQLException {
        PGSimpleDataSource dataSource = new PGSimpleDataSource();
        dataSource.setUrl(URL);
        dataSource.setUser(USERNAME);
        dataSource.setPassword(PASSWORD);
        return dataSource;
    }
}