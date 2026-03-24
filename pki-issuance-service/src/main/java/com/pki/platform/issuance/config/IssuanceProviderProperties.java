package com.pki.platform.issuance.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "pki.issuance")
public class IssuanceProviderProperties {

    private final Provider provider = new Provider();
    private final SignerConfig signer = new SignerConfig();

    public Provider getProvider() {
        return provider;
    }

    public SignerConfig getSigner() {
        return signer;
    }

    public static class Provider {

        private String type = "local-x509";

        public String getType() {
            return type;
        }

        public void setType(String type) {
            this.type = type;
        }
    }

    public static class SignerConfig {

        private String type = "soft";
        private final Soft soft = new Soft();

        public String getType() {
            return type;
        }

        public void setType(String type) {
            this.type = type;
        }

        public Soft getSoft() {
            return soft;
        }
    }

    public static class Soft {

        private String keystorePath;
        private String keystorePassword;
        private String keyAlias;
        private String keyPassword;
        private String certificatePath;
        private String privateKeyPath;
        private String signatureAlgorithm = "SHA256withRSA";

        public String getKeystorePath() {
            return keystorePath;
        }

        public void setKeystorePath(String keystorePath) {
            this.keystorePath = keystorePath;
        }

        public String getKeystorePassword() {
            return keystorePassword;
        }

        public void setKeystorePassword(String keystorePassword) {
            this.keystorePassword = keystorePassword;
        }

        public String getKeyAlias() {
            return keyAlias;
        }

        public void setKeyAlias(String keyAlias) {
            this.keyAlias = keyAlias;
        }

        public String getKeyPassword() {
            return keyPassword;
        }

        public void setKeyPassword(String keyPassword) {
            this.keyPassword = keyPassword;
        }

        public String getCertificatePath() {
            return certificatePath;
        }

        public void setCertificatePath(String certificatePath) {
            this.certificatePath = certificatePath;
        }

        public String getPrivateKeyPath() {
            return privateKeyPath;
        }

        public void setPrivateKeyPath(String privateKeyPath) {
            this.privateKeyPath = privateKeyPath;
        }

        public String getSignatureAlgorithm() {
            return signatureAlgorithm;
        }

        public void setSignatureAlgorithm(String signatureAlgorithm) {
            this.signatureAlgorithm = signatureAlgorithm;
        }
    }
}
