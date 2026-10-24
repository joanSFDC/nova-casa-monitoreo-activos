import { LightningElement, api } from "lwc";
import { EVENTO, pulsoDetenido } from "c/animacionSeveridad";

const CLASES = {
  Critico: "critico",
  Advertencia: "advertencia",
  Normal: "normal"
};

const ETIQUETAS = {
  Critico: "Crítico",
  Advertencia: "Advertencia",
  Normal: "Normal"
};

/**
 * La severidad con su color y un punto. El texto siempre va escrito: el color
 * ayuda a ver, pero no es lo único que la distingue. En advertencia y en crítico
 * el punto pulsa, más rápido en crítico, salvo que la persona lo haya detenido.
 */
export default class PastillaSeveridad extends LightningElement {
  @api severidad;
  @api etiqueta;

  quieta = false;

  connectedCallback() {
    this.quieta = pulsoDetenido();
    this.alCambiarPulso = (event) => {
      this.quieta = Boolean(event.detail && event.detail.detenido);
    };
    window.addEventListener(EVENTO, this.alCambiarPulso);
  }

  disconnectedCallback() {
    window.removeEventListener(EVENTO, this.alCambiarPulso);
  }

  get clase() {
    return (
      "pastilla pastilla_" +
      (CLASES[this.severidad] || "sin-datos") +
      (this.quieta ? " pastilla_quieta" : "")
    );
  }

  get texto() {
    return this.etiqueta || ETIQUETAS[this.severidad] || "Sin datos";
  }
}
