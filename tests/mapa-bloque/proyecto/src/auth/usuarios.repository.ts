import { TIEMPO_SESION } from './auth.service.js';

export class UsuariosRepository {
  buscar(correo: string) {
    return correo ? { correo, clave: 'x', vence: TIEMPO_SESION } : null;
  }
}

export function contarUsuarios(): number {
  return 0;
}
