# ACAS (Java)

Java 21 / Spring Boot 3 port of ACAS, built alongside the COBOL sources. Nothing here is used by the COBOL build (`comp-all.sh`).

| Module | Contents |
|---|---|
| `acas-core` | Domain model and business services shared by the web UI and the REST API |
| `acas-isam` | Readers and writers for the legacy GnuCOBOL data files |
| `acas-app` | Spring Boot application (web UI, `/api/v1`, actuator endpoints) |

Migration plan: `docs/migration/java-ipad-pr-plan.md`.

## Build and run

```sh
cd java
./mvnw verify                                  # build and run all tests
java -jar acas-app/target/acas-app-*.jar       # starts on port 8080 (override with PORT)
curl localhost:8080/actuator/health            # {"status":"UP",...}
```

Endpoints: `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness`, `/actuator/info`.

CI: `.github/workflows/java.yml` runs `./mvnw verify`, then starts the jar and checks the health endpoint. It runs only when `java/**` or the workflow changes.
