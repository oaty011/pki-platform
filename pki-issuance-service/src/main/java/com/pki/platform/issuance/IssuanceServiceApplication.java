package com.pki.platform.issuance;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@MapperScan("com.pki.platform.issuance.mapper")
@SpringBootApplication
@EnableScheduling
public class IssuanceServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(IssuanceServiceApplication.class, args);
    }
}
