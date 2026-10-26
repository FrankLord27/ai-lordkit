import { UsuariosRepository } from './usuarios.repository.js';
import type { LoginDto } from './dto/login.dto.js';
import { hashear } from '../shared/hash.js';

export const TIEMPO_SESION = 3600;

export class AuthService {
  private repo = new UsuariosRepository();

  login(dto: LoginDto) {
    const usuario = this.repo.buscar(dto.correo);
    return usuario?.clave === hashear(dto.clave);
  }
}

export function validarCorreo(correo: string): boolean {
  return correo.includes('@');
}
