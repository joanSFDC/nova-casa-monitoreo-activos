import { LightningElement, api } from "lwc";

const CLASES = {
  WATER_PUMP: "bomba",
  WATER_METER: "agua",
  ENERGY_METER: "energia",
  TECHNICAL_ROOM: "sala",
  SECURITY_CAMERA: "camara"
};

/**
 * El dibujo del tipo de equipo. Es decorativo: el nombre del tipo va siempre
 * escrito al lado, así que el ícono no se anuncia.
 */
export default class IconoEquipo extends LightningElement {
  @api tipo;

  get familia() {
    return CLASES[this.tipo] || "otro";
  }

  get clase() {
    return "icono icono_" + this.familia;
  }

  get esBomba() {
    return this.familia === "bomba";
  }

  get esAgua() {
    return this.familia === "agua";
  }

  get esEnergia() {
    return this.familia === "energia";
  }

  get esSala() {
    return this.familia === "sala";
  }

  get esCamara() {
    return this.familia === "camara";
  }
}
