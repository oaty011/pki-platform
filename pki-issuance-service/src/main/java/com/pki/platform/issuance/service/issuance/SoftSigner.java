package com.pki.platform.issuance.service.issuance;

import com.pki.platform.issuance.config.IssuanceProviderProperties;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyFactory;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Base64;

public class SoftSigner implements Signer {

    private final IssuanceProviderProperties.Soft properties;

    private volatile X509Certificate issuerCertificate;
    private volatile PrivateKey privateKey;

    public SoftSigner(IssuanceProviderProperties.Soft properties) {
        this.properties = properties;
    }

    @Override
    public X509Certificate loadIssuerCertificate() {
        ensureLoaded();
        return issuerCertificate;
    }

    @Override
    public PrivateKey loadPrivateKey() {
        ensureLoaded();
        return privateKey;
    }

    @Override
    public byte[] sign(byte[] content, String signatureAlgorithm) {
        try {
            Signature signature = Signature.getInstance(signatureAlgorithm);
            signature.initSign(loadPrivateKey());
            signature.update(content);
            return signature.sign();
        } catch (Exception ex) {
            throw new IllegalStateException("failed to sign content with soft signer", ex);
        }
    }

    private void ensureLoaded() {
        if (issuerCertificate != null && privateKey != null) {
            return;
        }
        synchronized (this) {
            if (issuerCertificate != null && privateKey != null) {
                return;
            }
            if (hasText(properties.getKeystorePath())) {
                loadFromPkcs12();
                return;
            }
            if (hasText(properties.getCertificatePath()) && hasText(properties.getPrivateKeyPath())) {
                loadFromPem();
                return;
            }
            throw new IllegalStateException(
                "soft signer is not configured: provide either keystorePath or certificatePath + privateKeyPath");
        }
    }

    private void loadFromPkcs12() {
        try (InputStream inputStream = openStream(properties.getKeystorePath())) {
            KeyStore keyStore = KeyStore.getInstance("PKCS12");
            keyStore.load(inputStream, toChars(properties.getKeystorePassword()));

            String alias = properties.getKeyAlias();
            if (!hasText(alias)) {
                throw new IllegalStateException("soft signer keyAlias is required when using PKCS12");
            }

            KeyStore.PrivateKeyEntry entry = (KeyStore.PrivateKeyEntry) keyStore.getEntry(
                alias,
                new KeyStore.PasswordProtection(resolveKeyPassword())
            );
            if (entry == null) {
                throw new IllegalStateException("soft signer key entry not found for alias=" + alias);
            }

            Certificate certificate = entry.getCertificate();
            if (!(certificate instanceof X509Certificate x509Certificate)) {
                throw new IllegalStateException("soft signer issuer certificate is not X509");
            }

            issuerCertificate = x509Certificate;
            privateKey = entry.getPrivateKey();
        } catch (Exception ex) {
            throw new IllegalStateException("failed to load soft signer material from PKCS12", ex);
        }
    }

    private void loadFromPem() {
        try {
            String certPem = readString(properties.getCertificatePath());
            String keyPem = readString(properties.getPrivateKeyPath());

            CertificateFactory certificateFactory = CertificateFactory.getInstance("X.509");
            issuerCertificate = (X509Certificate) certificateFactory.generateCertificate(
                new ByteArrayInputStream(certPem.getBytes(StandardCharsets.UTF_8))
            );

            String privateKeyBody = stripPemMarkers(keyPem, "PRIVATE KEY");
            byte[] privateKeyBytes = Base64.getMimeDecoder().decode(privateKeyBody);
            PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(privateKeyBytes);
            KeyFactory keyFactory = KeyFactory.getInstance("RSA");
            privateKey = keyFactory.generatePrivate(keySpec);
        } catch (Exception ex) {
            throw new IllegalStateException("failed to load soft signer material from PEM", ex);
        }
    }

    private InputStream openStream(String path) throws IOException {
        if (path.startsWith("classpath:")) {
            String resourcePath = path.substring("classpath:".length());
            InputStream inputStream = SoftSigner.class.getResourceAsStream(resourcePath.startsWith("/") ? resourcePath : "/" + resourcePath);
            if (inputStream == null) {
                throw new IOException("resource not found: " + path);
            }
            return inputStream;
        }
        return Files.newInputStream(Path.of(path));
    }

    private String readString(String path) throws IOException {
        try (InputStream inputStream = openStream(path)) {
            return new String(inputStream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private char[] resolveKeyPassword() {
        if (hasText(properties.getKeyPassword())) {
            return properties.getKeyPassword().toCharArray();
        }
        return toChars(properties.getKeystorePassword());
    }

    private char[] toChars(String value) {
        return value == null ? null : value.toCharArray();
    }

    private String stripPemMarkers(String pem, String marker) {
        String begin = "-----BEGIN " + marker + "-----";
        String end = "-----END " + marker + "-----";
        return pem.replace(begin, "")
            .replace(end, "")
            .replaceAll("\\s+", "");
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }
}
