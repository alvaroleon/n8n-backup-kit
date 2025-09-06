# n8n Backup Kit (Docker)

Export and import **all n8n workflows and credentials** from a running Docker container.  
Backups are now produced as a compressed `.tar.gz` archive and copied to your host.  
Credentials are exported **decrypted** and automatically re-encrypted on import using the destination container’s `N8N_ENCRYPTION_KEY`.

> **⚠️ Security:** Never commit real encryption keys or backups to source control.

---

## Prerequisites

- Bash (Linux/macOS)
- Docker CLI (`docker`)
- `tar` available on the host
- A running n8n container (ID **or** name)
- A bind-mounted shared directory inside the container (e.g. `/home/node/shared`)

---

## Finding Your `N8N_ENCRYPTION_KEY`

If you do not have the `N8N_ENCRYPTION_KEY` set as an environment variable, you can retrieve it from the container itself:

```bash
docker exec -it <container_id_or_name> sh
cd /home/node/.n8n
cat config | grep encryptionKey
```

Copy this value and set it in your `.env` as `N8N_ENCRYPTION_KEY`.

---

## Quick Start

1. **Clone** this repository and `cd` into it.

2. **Create your `.env`** from the example:

```bash
cp .env.example .env
vim .env
```

Set:

- `CID` — container ID or name of your n8n container
- `N8N_ENCRYPTION_KEY` — the encryption key used by the container
- `SHARED_DIR` — absolute path inside the container (bind-mounted)
- Optional: `OUTPUT_DIR`, `BACKUP_PREFIX`

3. **Export** (workflows + credentials) to a compressed file:

```bash
chmod +x export-n8n.sh
./export-n8n.sh
```

Output:

- `./n8n-backup-YYYYMMDD_HHMMSSUTC.tar.gz`

4. **Import** into a (possibly different) n8n container. The script supports both directories and `.tar.gz` archives:

```bash
chmod +x import-n8n.sh
./import-n8n.sh ./n8n-backup-YYYYMMDD_HHMMSSUTC.tar.gz
```

---

## What Gets Created

Inside the archive:

```bash
workflows.json
credentials.json
```

- **Export** uses:

  - `n8n export:workflow --all --output=...`
  - `n8n export:credentials --all --decrypted --output=...`

- **Import** uses:
  - `n8n import:workflow --separate --input=...`
  - `n8n import:credentials --separate --input=...`

> The import **automatically re-encrypts** credentials using the container’s own `N8N_ENCRYPTION_KEY` (it does not need the key from the export).

---

## Notes & Tips

- **Container reference:** `CID` may be a container **ID** or **name**.
- **Docker Swarm/Kubernetes:** Works as long as the container is reachable via `docker exec` and the path in `SHARED_DIR` exists.
- **Permissions:** Scripts run `docker exec -u node`, matching the official n8n image. Adjust if your image differs.
- **Rotation:** Add the export to `cron` and remove older `.tar.gz` files automatically.

Example cron (daily at 03:10):

```bash
10 3 * * * cd /opt/n8n-backup-kit && ./export-n8n.sh >> export.log 2>&1
```

Rotate backups older than 14 days (host-side):

```bash
find . -maxdepth 1 -type f -name 'n8n-backup-*.tar.gz' -mtime +14 -delete
```

---

## Troubleshooting

- `Container 'XYZ' not running`: start your container and retry.
- `n8n: not found` inside the container: ensure the n8n CLI is available in the image.
- Permissions issues: verify your `SHARED_DIR` is writable by user `node` (or adjust `-u` and ownership).

---

## Security Checklist

- Keep `.env` out of source control.
- Store backups in a restricted location.
- Consider GPG/zstd encryption outside these scripts if you need at-rest encryption.
- Rotate keys periodically.

---

# n8n Backup Kit (Docker) — Español

Exporta e importa **todos los workflows y credenciales** de n8n desde un contenedor Docker en ejecución.  
Los backups ahora se generan como un archivo comprimido `.tar.gz` y se copian al host.  
Las credenciales se exportan **descifradas** y se vuelven a cifrar automáticamente en la importación usando la `N8N_ENCRYPTION_KEY` del contenedor de destino.

> **⚠️ Seguridad:** Nunca subas tus llaves reales ni backups a un repositorio público.

---

## Requisitos

- Bash (Linux/macOS)
- CLI de Docker (`docker`)
- `tar` disponible en el host
- Un contenedor n8n en ejecución (ID **o** nombre)
- Una carpeta compartida (bind mount) dentro del contenedor (por ejemplo `/home/node/shared`)

---

## Cómo encontrar tu `N8N_ENCRYPTION_KEY`

Si no tienes configurada la variable de entorno `N8N_ENCRYPTION_KEY`, puedes obtenerla desde el contenedor:

```bash
docker exec -it <container_id_or_name> sh
cd /home/node/.n8n
cat config | grep encryptionKey
```

Copia ese valor y colócalo en tu `.env` como `N8N_ENCRYPTION_KEY`.

---

## Guía Rápida

1. **Clona** este repositorio y entra en él con `cd`.
2. **Crea tu `.env`** a partir del ejemplo:

```bash
cp .env.example .env
vim .env
```

Configura:

- `CID` — ID o nombre del contenedor de n8n
- `N8N_ENCRYPTION_KEY` — la clave de cifrado usada por el contenedor
- `SHARED_DIR` — ruta absoluta dentro del contenedor (bind-mounted)
- Opcional: `OUTPUT_DIR`, `BACKUP_PREFIX`

3. **Exporta** (workflows + credenciales) a un archivo comprimido:

```bash
chmod +x export-n8n.sh
./export-n8n.sh
```

Salida:

- `./n8n-backup-YYYYMMDD_HHMMSSUTC.tar.gz`

4. **Importa** en otro contenedor (acepta carpeta o `.tar.gz`):

```bash
chmod +x import-n8n.sh
./import-n8n.sh ./n8n-backup-YYYYMMDD_HHMMSSUTC.tar.gz
```

---

## Qué se genera

Dentro del archivo comprimido:

```bash
workflows.json
credentials.json
```

- **Export** usa:

  - `n8n export:workflow --all --output=...`
  - `n8n export:credentials --all --decrypted --output=...`

- **Import** usa:
  - `n8n import:workflow --separate --input=...`
  - `n8n import:credentials --separate --input=...`

> La importación **recifra automáticamente** las credenciales usando la `N8N_ENCRYPTION_KEY` del contenedor de destino (no necesita la key del export).

---

## Notas y Consejos

- `CID` puede ser ID o nombre del contenedor.
- Funciona en Docker Swarm/Kubernetes mientras el contenedor sea accesible con `docker exec`.
- Los scripts usan `-u node`, que coincide con la imagen oficial de n8n. Ajusta si tu contenedor usa otro usuario.
- **Rotación de backups:** programa el export con cron y elimina archivos `.tar.gz` viejos automáticamente.

Ejemplo de cron diario a las 03:10:

```bash
10 3 * * * cd /opt/n8n-backup-kit && ./export-n8n.sh >> export.log 2>&1
```

Rotar backups de más de 14 días:

```bash
find . -maxdepth 1 -type f -name 'n8n-backup-*.tar.gz' -mtime +14 -delete
```

---

## Solución de Problemas

- `Container 'XYZ' not running`: Inicia el contenedor y reintenta.
- `n8n: not found`: Asegúrate que el CLI de n8n está instalado en la imagen.
- Problemas de permisos: revisa que `SHARED_DIR` sea escribible por el usuario `node`.

---

## Checklist de Seguridad

- Nunca subas el `.env` a GitHub.
- Guarda los backups en un directorio seguro.
- Si necesitas cifrado en reposo, considera comprimir y cifrar con GPG fuera de estos scripts.
- Rota las claves periódicamente.

---

## Licencia

MIT
