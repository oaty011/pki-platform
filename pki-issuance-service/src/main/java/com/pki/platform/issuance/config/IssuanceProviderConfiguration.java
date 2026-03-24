package com.pki.platform.issuance.config;

import com.pki.platform.issuance.service.issuance.CertificateIssuanceProvider;
import com.pki.platform.issuance.service.issuance.LocalX509IssuanceProvider;
import com.pki.platform.issuance.service.issuance.Signer;
import com.pki.platform.issuance.service.issuance.SoftSigner;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(IssuanceProviderProperties.class)
public class IssuanceProviderConfiguration {

    @Bean
    public Signer signer(IssuanceProviderProperties properties) {
        String signerType = properties.getSigner().getType();
        if (!"soft".equalsIgnoreCase(signerType)) {
            throw new IllegalStateException("Only soft signer is supported in the current issuance skeleton");
        }
        return new SoftSigner(properties.getSigner().getSoft());
    }

    @Bean
    public CertificateIssuanceProvider certificateIssuanceProvider(Signer signer,
                                                                   IssuanceProviderProperties properties) {
        String providerType = properties.getProvider().getType();
        if (!"local-x509".equalsIgnoreCase(providerType)) {
            throw new IllegalStateException("Only local-x509 provider is supported in the current issuance skeleton");
        }
        return new LocalX509IssuanceProvider(signer, properties.getSigner().getSoft().getSignatureAlgorithm());
    }
}
