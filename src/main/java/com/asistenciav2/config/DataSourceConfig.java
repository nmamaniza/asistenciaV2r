package com.asistenciav2.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import com.asistenciav2.util.DatabaseConnection;

import javax.sql.DataSource;
import java.sql.SQLException;

@Configuration
public class DataSourceConfig {

    @Bean
    public DataSource dataSource() throws SQLException {
        // Utilizamos la conexión existente en la aplicación
        return DatabaseConnection.getDataSource();
    }
}