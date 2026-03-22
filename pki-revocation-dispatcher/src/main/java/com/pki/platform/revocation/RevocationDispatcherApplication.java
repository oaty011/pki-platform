package com.pki.platform.revocation;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@MapperScan("com.pki.platform.revocation.mapper")
@SpringBootApplication
public class RevocationDispatcherApplication {

    public static void main(String[] args) {
        SpringApplication.run(RevocationDispatcherApplication.class, args);
    }
}
