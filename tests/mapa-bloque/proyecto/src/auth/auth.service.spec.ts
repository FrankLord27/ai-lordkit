import { AuthService } from './auth.service.js';

const s = new AuthService();
if (s.login({ correo: 'a@b.c', clave: 'x' }) !== false) throw new Error('falló');
import { validarCorreo } from './auth.service.js';

if (!validarCorreo('a@b.c')) throw new Error('correo');
