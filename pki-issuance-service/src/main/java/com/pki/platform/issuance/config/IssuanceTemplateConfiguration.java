package com.pki.platform.issuance.config;

import com.pki.platform.issuance.template.CertificateTemplateRegistry;
import java.util.Properties;
import org.springframework.boot.context.properties.bind.Bindable;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.ConfigurationPropertySources;
import org.springframework.core.env.PropertiesPropertySource;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.beans.factory.config.YamlPropertiesFactoryBean;

@Configuration(proxyBeanMethods = false)
public class IssuanceTemplateConfiguration {

    @Bean
    public IssuanceTemplateProperties issuanceTemplateProperties() {
        YamlPropertiesFactoryBean yaml = new YamlPropertiesFactoryBean();
        yaml.setResources(new ClassPathResource("issuance-templates.yml"));
        Properties yamlProperties = yaml.getObject();
        if (yamlProperties == null || yamlProperties.isEmpty()) {
            throw new IllegalStateException("issuance-templates.yml is missing or empty");
        }

        Binder binder = new Binder(ConfigurationPropertySources.from(
            new PropertiesPropertySource("issuanceTemplates", yamlProperties)
        ));
        IssuanceTemplateProperties properties = binder.bind("", Bindable.of(IssuanceTemplateProperties.class))
            .orElseThrow(() -> new IllegalStateException("failed to bind issuance-templates.yml"));
        properties.validate();
        return properties;
    }

    @Bean
    public CertificateTemplateRegistry certificateTemplateRegistry(IssuanceTemplateProperties properties) {
        return new CertificateTemplateRegistry(properties);
    }
}
