package com.asistenciav2.config;

import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;

/**
 * Configuración principal de la aplicación Spring
 * Esta clase habilita el escaneo de componentes y centraliza la configuración
 */
@Configuration
@ComponentScan(basePackages = "com.asistenciav2")
@Import({ SecurityConfig.class, DataSourceConfig.class })
public class AppConfig {
    // Configuración principal de la aplicación
    // El escaneo de componentes detectará automáticamente todos los servlets,
    // servicios y otros componentes anotados en el paquete com.asistenciav2
}
