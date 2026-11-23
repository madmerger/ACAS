# ACAS (Java)

Java 21 / Spring Boot 4 port of ACAS, built alongside the COBOL sources. Nothing here is used by the COBOL build (`comp-all.sh`).

| Module | Contents |
|---|---|
| `acas-core` | Domain model and business services shared by the web UI and the REST API |
| `acas-isam` | Readers and writers for the legacy GnuCOBOL data files |
| `acas-app` | Spring Boot application (web UI, `/api/v1`, actuator endpoints) |

Migration plan: `docs/migration/java-ipad-pr-plan.md`.

## COBOL codecs

`acas-isam` provides `com.acas.isam.codec`: packed decimal, big-endian
PIC binary, native binary (explicit byte order, little-endian by default),
display overpunch and integer dates. PIC codecs take total digits and scale.
Native binary takes a byte size (1/2/4/8) and signed flag; unsigned 8-byte
values are not supported by the COBOL BINARY-DOUBLE mapping. Invalid values
and buffer bounds throw `CobolDataException`; codecs never truncate.
`acas-core` provides `CobolNumeric.store` for COBOL assignment rounding,
high-order truncation and unsigned absolute-value semantics.

## Build and run

```sh
cd java
./mvnw verify                                  # build and run all tests
java -jar acas-app/target/acas-app-*.jar       # starts on port 8080 (override with PORT)
curl localhost:8080/actuator/health            # {"status":"UP",...}
```

Endpoints: `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness`. No other actuator endpoint is exposed.

CI: `.github/workflows/java.yml` runs `./mvnw verify`, then starts the jar and checks the health endpoint. It runs only when `java/**` or the workflow changes.
