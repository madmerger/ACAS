package com.acas.core;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class AcasSystemTest {

    @Test
    void namesTheLegacySystem() {
        assertThat(AcasSystem.NAME).isEqualTo("ACAS");
        assertThat(AcasSystem.FULL_NAME).isEqualTo("Applewood Computers Accounting System");
    }
}
