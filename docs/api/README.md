<!-- SPDX-License-Identifier: (see LICENSE) -->

# Mayam — API Reference

This directory contains the **OpenAPI 3.1** specifications for the two HTTP API
surfaces exposed by the Mayam PACS server.

---

## Specifications

| File | Description | Default Port |
|---|---|---|
| [`admin-api.yaml`](admin-api.yaml) | Administration REST API — authentication, node management, storage, worklist, MPPS, webhooks, LDAP, backup, HSM, and system settings. | `8081` (prefix `/admin/api/`) |
| [`dicomweb-api.yaml`](dicomweb-api.yaml) | DICOMweb & FHIR API — QIDO-RS, WADO-RS, STOW-RS, UPS-RS, WADO-URI, FHIR R4 endpoints (Patient, ImagingStudy, DiagnosticReport, Endpoint), Prometheus metrics, and health checks. | `8080` |

---

## Viewing the Specifications

You can explore these specifications with any OpenAPI-compatible viewer. A few
options are listed below.

### Swagger UI (Docker)

```bash
docker run -d -p 9090:8080 \
  -e SWAGGER_JSON=/specs/admin-api.yaml \
  -v "$(pwd)":/specs \
  swaggerapi/swagger-ui
```

Then open <http://localhost:9090> in your browser. Replace `admin-api.yaml` with
`dicomweb-api.yaml` to view the DICOMweb specification.

### Redoc (Docker)

```bash
docker run -d -p 9091:80 \
  -e SPEC_URL=/specs/dicomweb-api.yaml \
  -v "$(pwd)":/usr/share/nginx/html/specs \
  redocly/redoc
```

Then open <http://localhost:9091> in your browser.

### Redocly CLI (local)

```bash
npx @redocly/cli preview-docs admin-api.yaml
```

### Online Viewers

You can also paste or upload the YAML files into any of the following online
tools:

- [Swagger Editor](https://editor.swagger.io)
- [Redocly](https://redocly.com)
- [Stoplight Studio](https://stoplight.io/studio)

---

## Authentication

The **Admin API** requires a valid JWT bearer token for all endpoints except
`POST /auth/login` and `POST /setup/*`. Obtain a token by posting credentials to
the login endpoint:

```bash
curl -X POST https://localhost:8081/admin/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "changeme"}'
```

The **DICOMweb API** authentication is configurable — see the
[Administrator Guide](../ADMINISTRATOR_GUIDE.md) for details on enabling JWT or
client-certificate authentication for DICOMweb endpoints.

---

## Further Reading

- [Administrator Guide](../ADMINISTRATOR_GUIDE.md) — full configuration
  reference including API port, TLS, and authentication settings.
- [Deployment Guide](../DEPLOYMENT_GUIDE.md) — network architecture and port
  mapping for Docker and bare-metal deployments.
- [Conformance Statement](../CONFORMANCE_STATEMENT.md) — DICOM and DICOMweb
  conformance details.
