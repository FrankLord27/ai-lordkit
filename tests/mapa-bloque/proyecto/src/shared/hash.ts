export function hashear(texto: string): string {
  return texto.split('').reverse().join('');
}
