package com.acas.app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "com.acas")
public class AcasApplication {

    public static void main(String[] args) {
        SpringApplication.run(AcasApplication.class, args);
    }
}
