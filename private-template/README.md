# Capa privada de ai-lordkit

Esta carpeta es la plantilla de **tu** capa privada: lo que es solo tuyo y no debe ir al repo público. `./install.sh private-init` la copia a `~/ai-lordkit-private` (o a `$CLAUDE_PRIVATE_DIR`) y le hace `git init`.

Súbela a un repo **privado** tuyo para tenerla en todas tus máquinas:

```bash
cd ~/ai-lordkit-private
git remote add origin git@github.com:<tu-usuario>/ai-lordkit-private.git
git push -u origin main
```

En otra máquina: clónala en `~/ai-lordkit-private` antes de correr `./install.sh`.

## Qué va aquí

| Archivo / carpeta    | Qué hace install.sh con él                                                         |
| -------------------- | ---------------------------------------------------------------------------------- |
| `CLAUDE.md`          | Se agrega al final de `~/.claude/CLAUDE.md`, debajo de una línea marcadora          |
| `settings.json`      | Se mezcla encima del `settings.json` público (los arrays se suman, no se pisan)     |
| `skills/`, `agents/`, `commands/` | Se copian a `~/.claude/`, igual que las públicas                       |
| `mcp.json`           | Tus servidores MCP privados, mismo formato que `mcp/servers.json`                  |
| `private-terms.txt`  | Palabras que **nunca** deben salir en el repo público (clientes, proyectos, tu email). El escáner falla si las ve |

## Qué NO va aquí

Tokens, llaves ni contraseñas, ni siquiera en un repo privado. Esos van en variables de entorno, en `~/.claude/*.key` (con `chmod 600`) o en tu gestor de contraseñas. `install.sh sync` se niega a subir algo que parezca un token, también en este repo.
