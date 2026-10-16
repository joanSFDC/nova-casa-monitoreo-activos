import { LightningElement, api } from "lwc";

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
 * ayuda a ver, pero no es lo único que la distingue.
 */
export default class PastillaSeveridad extends LightningElement {
  @api severidad;
  @api etiqueta;

  get clase() {
    return "pastilla pastilla_" + (CLASES[this.severidad] || "sin-datos");
  }

  get texto() {
    return this.etiqueta || ETIQUETAS[this.severidad] || "Sin datos";
  }
}
