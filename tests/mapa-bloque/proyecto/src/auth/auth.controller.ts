import { AuthService } from './auth.service.js';
import type { LoginDto } from './dto/login.dto.js';

export class AuthController {
  constructor(private readonly auth: AuthService) {}

  login(dto: LoginDto) {
    const intentos = 0; // la IA la dejó aquí y nunca la usa
    return this.auth.login(dto);
  }
}
