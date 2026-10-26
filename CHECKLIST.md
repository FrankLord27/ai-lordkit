# Checklist de pre-requisitos — Equipo de Agents

Antes de usar el equipo completo (especialmente `git-workflow`), asegúrate de tener estos pre-requisitos. `./install.sh doctor` verifica cada uno automáticamente, pero aquí está el detalle de cómo configurarlos si te faltan.

---

## 1. GitHub CLI (`gh`)

El agent `git-workflow` necesita `gh` para crear PRs, agregar labels, ver el estado del CI, etc.

### Instalar en Ubuntu

```bash
sudo apt update
sudo apt install gh
```

Verifica:

```bash
gh --version
```

### Autenticar

```bash
gh auth login
```

Te preguntará:

- **What account do you want to log into?** → GitHub.com
- **What is your preferred protocol for Git operations?** → HTTPS (más simple) o SSH (más seguro)
- **Authenticate Git with your GitHub credentials?** → Y
- **How would you like to authenticate?** → Login with a web browser

Verifica que quedó:

```bash
gh auth status
```

Debe decir: `✓ Logged in to github.com as <tu-usuario>`

---

## 2. Configuración global de Git

Sin esto, los commits no tienen autor.

```bash
git config --global user.name "Tu Nombre"
git config --global user.email "tu-email@example.com"
```

Verifica:

```bash
git config --global --list | grep user
```

---

## 3. Firma de commits con GPG

Decidiste que TODOS los commits deben estar firmados. Configuración completa:

### Verificar si ya tienes una key GPG

```bash
gpg --list-secret-keys --keyid-format=long
```

Si ves algo como `sec   rsa4096/ABC1234567890DEF 2024-...`, ya tienes una key. Si no, créala.

### Crear una nueva key GPG

```bash
gpg --full-generate-key
```

Responde:

- **Type of key:** RSA and RSA (default)
- **Key size:** 4096
- **Validity:** 0 (no expira) o 2y si prefieres rotación
- **Real name:** tu nombre
- **Email:** el mismo de tu cuenta (DEBE coincidir con el email de Git/GitHub)
- **Passphrase:** una segura — la necesitarás cada vez que firmes (o usa gpg-agent para cachearla)

### Obtener el ID de la key

```bash
gpg --list-secret-keys --keyid-format=long
# Busca la línea: sec   rsa4096/ABC1234567890DEF
# El ID es: ABC1234567890DEF
```

### Configurar Git para usar la key

```bash
git config --global user.signingkey ABC1234567890DEF   # reemplaza con tu ID
git config --global commit.gpgsign true
git config --global tag.gpgSign true
```

### Exportar y subir la key pública a GitHub

```bash
gpg --armor --export ABC1234567890DEF
```

Copia toda la salida (desde `-----BEGIN PGP PUBLIC KEY BLOCK-----` hasta `-----END PGP PUBLIC KEY BLOCK-----`).

Luego:

1. Ve a https://github.com/settings/gpg/new
2. Pega el bloque
3. Click "Add GPG key"

O directamente con `gh`:

```bash
gpg --armor --export ABC1234567890DEF | gh gpg-key add -
```

### Verificar firma

```bash
echo "test" > /tmp/test-sign.txt
git -C /tmp init -q test-repo && cd /tmp/test-repo
git commit --allow-empty -m "test: verificación de firma"
git log --show-signature -1
```

Debe decir: `gpg: Good signature from "Tu Nombre <...>"` y `Primary key fingerprint: ...`

### Alternativa: firmar con SSH key (más simple)

Si prefieres SSH en vez de GPG (es soportado desde Git 2.34+):

```bash
git config --global gpg.format ssh
git config --global user.signingkey "$HOME/.ssh/id_ed25519.pub"   # o tu key pública
git config --global commit.gpgsign true
```

Sube la SSH key a GitHub como "Signing key" (separado de la auth key) en https://github.com/settings/ssh/new

---

## 4. Cache de passphrase GPG (opcional pero recomendado)

Si firmas mucho, ingresar la passphrase cada vez es tedioso. Configura `gpg-agent`:

```bash
mkdir -p ~/.gnupg
cat >> ~/.gnupg/gpg-agent.conf << 'EOF'
default-cache-ttl 28800
max-cache-ttl 86400
EOF
gpg-connect-agent reloadagent /bye
```

Esto cachea la passphrase 8 horas (28800 segundos) tras el primer uso.

---

## 5. pnpm (para tu stack Turborepo)

```bash
# Si no lo tienes
npm install -g pnpm

# Verifica
pnpm --version
```

---

## 6. Variables de entorno opcionales

Para que `git-workflow` use templates de PR consistentes, puedes añadir a tu `~/.zshrc`:

```bash
export GH_PROMPT_DISABLED=1   # gh no pregunta por confirmación en algunos comandos
```

---

## 7. Branch protection rules en GitHub (recomendado)

En cada repo, ve a `Settings → Branches → Add rule` para `main` y activa:

- ✓ Require a pull request before merging
- ✓ Require status checks to pass before merging (si tienes CI)
- ✓ Require signed commits
- ✓ Require linear history (para que squash merge sea consistente)
- ✓ Do not allow bypassing the above settings (incluso para admins)

Esto refuerza desde el lado del servidor lo que `git-workflow` ya hace desde el lado del cliente.

---

## Resumen: comando único para verificar todo

```bash
echo "=== Git ===" && git --version
echo "=== Git config ===" && git config --global --list | grep -E "user|sign"
echo "=== gh ===" && gh --version && gh auth status
echo "=== GPG ===" && gpg --list-secret-keys --keyid-format=long
echo "=== pnpm ===" && pnpm --version
echo "=== Claude ===" && claude --version
```

Si TODOS responden sin errores, el equipo de agents está listo para operar al 100%.

---

## Troubleshooting común

### "gpg: signing failed: Inappropriate ioctl for device"

Falta configurar el TTY del gpg-agent. Añade a tu `~/.zshrc`:

```bash
export GPG_TTY=$(tty)
```

Y recarga: `source ~/.zshrc`

### "error: gpg failed to sign the data"

Verifica que la key esté disponible:

```bash
echo "test" | gpg --clearsign
```

Si falla, probablemente el agent no encuentra la passphrase. Reinicia el agent:

```bash
gpgconf --kill gpg-agent
```

### gh dice "auth required" en operaciones específicas

Algunos comandos requieren scopes adicionales. Reauténticate con scopes amplios:

```bash
gh auth refresh -h github.com -s repo,workflow,write:org
```
