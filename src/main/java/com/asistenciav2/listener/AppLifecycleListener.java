package com.asistenciav2.listener;

import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;
import java.sql.Driver;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Enumeration;
import java.util.logging.Logger;

public class AppLifecycleListener implements ServletContextListener {

    private static final Logger logger = Logger.getLogger(AppLifecycleListener.class.getName());

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        // Nada específico al inicio
    }

    @Override
    public void contextDestroyed(ServletContextEvent sce) {
        // Desregistrar drivers JDBC para evitar fugas de memoria en recargas
        Enumeration<Driver> drivers = DriverManager.getDrivers();
        while (drivers.hasMoreElements()) {
            Driver driver = drivers.nextElement();
            // Solo desregistrar drivers cargados por esta aplicación
            if (driver.getClass().getClassLoader() == getClass().getClassLoader()) {
                try {
                    DriverManager.deregisterDriver(driver);
                    logger.info("JDBC Driver desregistrado exitosamente: " + driver);
                } catch (SQLException e) {
                    logger.warning("Error desregistrando JDBC driver: " + driver + ". Error: " + e.getMessage());
                }
            }
        }
    }
}
