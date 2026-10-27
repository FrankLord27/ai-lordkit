import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';

export class AuthModule {
  static controllers = [AuthController];
  static providers = [AuthService];
}
