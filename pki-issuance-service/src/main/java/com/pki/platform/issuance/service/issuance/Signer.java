package com.pki.platform.issuance.service.issuance;

import java.security.PrivateKey;
import java.security.cert.X509Certificate;

public interface Signer {

    X509Certificate loadIssuerCertificate();

    PrivateKey loadPrivateKey();

    byte[] sign(byte[] content, String signatureAlgorithm);
}
