/**
 * Si el pulso de la severidad está detenido. Lo decide la persona con el botón
 * del monitor y se recuerda en este navegador: las pautas de accesibilidad piden
 * poder detener lo que se mueve más de 5 segundos. «Reducir movimiento» del
 * sistema lo apaga aparte, en el CSS de la pastilla.
 */
const CLAVE = "novaCasa.pulsoSeveridad";
const DETENIDO = "detenido";
export const EVENTO = "novacasapulso";

export function pulsoDetenido() {
  try {
    return window.localStorage.getItem(CLAVE) === DETENIDO;
  } catch {
    return false;
  }
}

export function detenerPulso(detener) {
  try {
    if (detener) {
      window.localStorage.setItem(CLAVE, DETENIDO);
    } else {
      window.localStorage.removeItem(CLAVE);
    }
  } catch {
    // Sin almacenamiento local, el cambio dura lo que dure la página.
  }
  window.dispatchEvent(
    new CustomEvent(EVENTO, { detail: { detenido: detener } })
  );
}
