package com.pki.platform.appdomain;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@MapperScan("com.pki.platform.appdomain.mapper")
@SpringBootApplication
public class AppDomainServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(AppDomainServiceApplication.class, args);
    }
}
