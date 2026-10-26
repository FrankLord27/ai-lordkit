export interface LoginDto {
  correo: string;
  clave: string;
}

export interface RegistroDto extends LoginDto {
  nombre: string;
}
