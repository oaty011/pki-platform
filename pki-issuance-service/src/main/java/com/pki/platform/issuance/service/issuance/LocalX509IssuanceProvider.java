package com.pki.platform.issuance.service.issuance;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import java.io.IOException;
import java.io.StringReader;
import java.io.StringWriter;
import java.math.BigInteger;
import java.security.GeneralSecurityException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Security;
import java.security.cert.X509Certificate;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.Date;
import java.util.UUID;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x500.X500NameBuilder;
import org.bouncycastle.asn1.x500.style.BCStyle;
import org.bouncycastle.asn1.x509.AuthorityKeyIdentifier;
import org.bouncycastle.asn1.x509.BasicConstraints;
import org.bouncycastle.asn1.x509.Extension;
import org.bouncycastle.asn1.x509.ExtendedKeyUsage;
import org.bouncycastle.asn1.x509.KeyUsage;
import org.bouncycastle.asn1.x509.KeyPurposeId;
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo;
import org.bouncycastle.asn1.x509.SubjectKeyIdentifier;
import org.bouncycastle.cert.X509CertificateHolder;
import org.bouncycastle.cert.X509v3CertificateBuilder;
import org.bouncycastle.cert.jcajce.JcaX509CertificateHolder;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509ExtensionUtils;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.openssl.PEMParser;
import org.bouncycastle.openssl.jcajce.JcaPEMWriter;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.DefaultSignatureAlgorithmIdentifierFinder;
import org.bouncycastle.operator.OperatorCreationException;
import org.bouncycastle.pkcs.PKCS10CertificationRequest;
import org.bouncycastle.pkcs.PKCSException;
import org.bouncycastle.pkcs.jcajce.JcaPKCS10CertificationRequest;
import org.bouncycastle.operator.jcajce.JcaContentVerifierProviderBuilder;

public class LocalX509IssuanceProvider implements CertificateIssuanceProvider {

    private static final BouncyCastleProvider BC_PROVIDER = new BouncyCastleProvider();

    static {
        Security.addProvider(BC_PROVIDER);
    }

    private final Signer signer;
    private final String defaultSignatureAlgorithm;

    public LocalX509IssuanceProvider(Signer signer, String defaultSignatureAlgorithm) {
        this.signer = signer;
        this.defaultSignatureAlgorithm = defaultSignatureAlgorithm;
    }

    @Override
    public CertificateIssuanceResult issue(CertificateIssuanceCommand command) {
        validate(command);

        try {
            X509Certificate issuerCertificate = signer.loadIssuerCertificate();
            PrivateKey privateKey = signer.loadPrivateKey();
            if (issuerCertificate == null || privateKey == null) {
                throw new IllegalStateException("Soft signer could not load issuer material");
            }

            SubjectMaterial subjectMaterial = resolveSubjectMaterial(command);
            OffsetDateTime notBefore = resolveNotBefore(command);
            OffsetDateTime notAfter = resolveNotAfter(command);
            String serialHex = prepareSerialNumber();
            BigInteger serialNumber = new BigInteger(serialHex, 16);

            X500Name issuerName = new JcaX509CertificateHolder(issuerCertificate).getSubject();
            X509v3CertificateBuilder builder = new X509v3CertificateBuilder(
                issuerName,
                serialNumber,
                toDate(notBefore),
                toDate(notAfter),
                subjectMaterial.subjectName(),
                SubjectPublicKeyInfo.getInstance(subjectMaterial.publicKey().getEncoded())
            );

            JcaX509ExtensionUtils extensionUtils = new JcaX509ExtensionUtils();
            SubjectKeyIdentifier subjectKeyIdentifier = extensionUtils.createSubjectKeyIdentifier(subjectMaterial.publicKey());
            AuthorityKeyIdentifier authorityKeyIdentifier = extensionUtils.createAuthorityKeyIdentifier(issuerCertificate);
            builder.addExtension(Extension.subjectKeyIdentifier, false, subjectKeyIdentifier);
            builder.addExtension(Extension.authorityKeyIdentifier, false, authorityKeyIdentifier);
            builder.addExtension(Extension.basicConstraints, true, new BasicConstraints(false));
            builder.addExtension(Extension.keyUsage, true, new KeyUsage(resolveKeyUsage(command)));
            if (command.isClientAuth()) {
                builder.addExtension(Extension.extendedKeyUsage, false, new ExtendedKeyUsage(KeyPurposeId.id_kp_clientAuth));
            }

            String signatureAlgorithm = resolveSignatureAlgorithm();
            X509CertificateHolder certificateHolder = builder.build(new DelegatingContentSigner(signer, signatureAlgorithm));
            X509Certificate certificate = new JcaX509CertificateConverter()
                .setProvider(BC_PROVIDER)
                .getCertificate(certificateHolder);
            certificate.verify(issuerCertificate.getPublicKey());

            return new CertificateIssuanceResult(
                serialHex.toLowerCase(),
                issuerCertificate.getSubjectX500Principal().getName(),
                "soft-signer",
                toPem(certificate),
                notAfter
            );
        } catch (BizException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new IllegalStateException("failed to issue local X.509 certificate", ex);
        }
    }

    public String prepareSerialNumber() {
        return UUID.randomUUID().toString().replace("-", "");
    }

    public OffsetDateTime resolveNotBefore(CertificateIssuanceCommand command) {
        return command.getNotBefore() == null ? OffsetDateTime.now() : command.getNotBefore();
    }

    public OffsetDateTime resolveNotAfter(CertificateIssuanceCommand command) {
        if (command.getNotAfter() == null) {
            throw new IllegalArgumentException("notAfter must be provided by the template-driven issuance command");
        }
        return command.getNotAfter();
    }

    public String resolveSignatureAlgorithm() {
        return defaultSignatureAlgorithm;
    }

    private SubjectMaterial resolveSubjectMaterial(CertificateIssuanceCommand command)
        throws IOException, GeneralSecurityException, OperatorCreationException, PKCSException {
        if (isBlank(command.getCsrPem())) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "csr is required");
        }

        try {
            PKCS10CertificationRequest certificationRequest = parseCsr(command.getCsrPem());
            JcaPKCS10CertificationRequest jcaRequest = new JcaPKCS10CertificationRequest(certificationRequest).setProvider(BC_PROVIDER);
            PublicKey publicKey = jcaRequest.getPublicKey();
            if (!certificationRequest.isSignatureValid(
                new JcaContentVerifierProviderBuilder().setProvider(BC_PROVIDER).build(publicKey))) {
                throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "csr signature verification failed");
            }
            X500Name subjectName = buildSubjectName(command);
            return new SubjectMaterial(publicKey, subjectName);
        } catch (BizException ex) {
            throw ex;
        } catch (IOException | PKCSException | OperatorCreationException | GeneralSecurityException ex) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "invalid csr format");
        }
    }

    private PKCS10CertificationRequest parseCsr(String csrPem) throws IOException {
        try (PEMParser pemParser = new PEMParser(new StringReader(csrPem))) {
            Object parsed = pemParser.readObject();
            if (parsed instanceof PKCS10CertificationRequest request) {
                return request;
            }
        }
        throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "invalid csr format");
    }

    private X500Name buildSubjectName(CertificateIssuanceCommand command) {
        if (!isBlank(command.getSubjectDn())) {
            return new X500Name(command.getSubjectDn());
        }
        X500NameBuilder builder = new X500NameBuilder(BCStyle.INSTANCE);
        builder.addRDN(BCStyle.CN, command.getSubjectId());
        if (!isBlank(command.getOrganization())) {
            builder.addRDN(BCStyle.O, command.getOrganization());
        }
        return builder.build();
    }

    private int resolveKeyUsage(CertificateIssuanceCommand command) {
        int usage = 0;
        if (command.isDigitalSignature()) {
            usage |= KeyUsage.digitalSignature;
        }
        if (command.isKeyEncipherment()) {
            usage |= KeyUsage.keyEncipherment;
        }
        if (usage == 0) {
            usage = KeyUsage.digitalSignature;
        }
        return usage;
    }

    private String resolveKeyAlgorithm(CertificateIssuanceCommand command) {
        return isBlank(command.getKeyAlgorithm()) ? "RSA" : command.getKeyAlgorithm();
    }

    private Date toDate(OffsetDateTime value) {
        return Date.from(Instant.from(value));
    }

    private String toPem(X509Certificate certificate) throws IOException {
        StringWriter stringWriter = new StringWriter();
        try (JcaPEMWriter pemWriter = new JcaPEMWriter(stringWriter)) {
            pemWriter.writeObject(certificate);
        }
        return stringWriter.toString();
    }

    private void validate(CertificateIssuanceCommand command) {
        if (command == null) {
            throw new IllegalArgumentException("issuance command is required");
        }
        if (isBlank(command.getRequestId()) || isBlank(command.getTemplateId()) || isBlank(command.getSubjectId())) {
            throw new IllegalArgumentException("requestId, templateId and subjectId are required");
        }
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    private record SubjectMaterial(PublicKey publicKey, X500Name subjectName) {
    }

    private static final class DelegatingContentSigner implements ContentSigner {

        private final java.io.ByteArrayOutputStream outputStream = new java.io.ByteArrayOutputStream();
        private final org.bouncycastle.asn1.x509.AlgorithmIdentifier algorithmIdentifier;
        private final Signer signer;
        private final String signatureAlgorithm;

        private DelegatingContentSigner(Signer signer, String signatureAlgorithm) {
            this.signer = signer;
            this.signatureAlgorithm = signatureAlgorithm;
            this.algorithmIdentifier = new DefaultSignatureAlgorithmIdentifierFinder().find(signatureAlgorithm);
        }

        @Override
        public org.bouncycastle.asn1.x509.AlgorithmIdentifier getAlgorithmIdentifier() {
            return algorithmIdentifier;
        }

        @Override
        public java.io.OutputStream getOutputStream() {
            return outputStream;
        }

        @Override
        public byte[] getSignature() {
            return signer.sign(outputStream.toByteArray(), signatureAlgorithm);
        }
    }
}
