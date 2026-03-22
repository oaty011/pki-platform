package com.pki.platform.ecudomain;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@MapperScan("com.pki.platform.ecudomain.mapper")
@SpringBootApplication
public class EcuDomainServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(EcuDomainServiceApplication.class, args);
    }
}
