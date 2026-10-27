import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import SENAL from "@salesforce/schema/Senal__c";
import LOCALE from "@salesforce/i18n/locale";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import pagina from "@salesforce/apex/LecturasPeriodoControlador.pagina";

export const TAMANO_PAGINA = 50;
export const VENTANA_DIAS = 7;

const CLASES = {
  Aplicado: "aplicado",
  Pendiente: "pendiente",
  Duplicado: "pendiente",
  Atrasado: "atrasado",
  Conflicto: "conflicto",
  Rechazado: "rechazado",
  Fallido: "fallido"
};

function fechaHora(valor) {
  if (!valor) {
    return "";
  }
  return new Intl.DateTimeFormat(LOCALE, {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: TIME_ZONE
  }).format(new Date(valor));
}

/**
 * Las lecturas del equipo durante el incidente, bajo demanda: la tarjeta entra
 * cerrada y no consulta nada hasta que se abre. Las páginas ya vistas quedan
 * guardadas y no se vuelven a pedir.
 */
export default class LecturasPeriodo extends NavigationMixin(LightningElement) {
  @api recordId;

  puedeVer = false;
  abierta = false;
  cargando = false;
  error;
  sinAcceso = false;
  paginas = [];
  indice = 0;

  // Sin lectura de la bitácora, la tarjeta no aparece.
  @wire(getObjectInfo, { objectApiName: SENAL })
  info({ data, error }) {
    if (data) {
      this.puedeVer = true;
    } else if (error) {
      this.puedeVer = false;
    }
  }

  get visible() {
    return this.puedeVer && !this.sinAcceso;
  }

  get textoBoton() {
    return this.abierta ? "Ocultar" : "Ver lecturas";
  }

  get expandida() {
    return this.abierta ? "true" : "false";
  }

  get sinAbrir() {
    return !this.abierta;
  }

  get actual() {
    return this.paginas[this.indice] || null;
  }

  get filas() {
    if (!this.actual) {
      return [];
    }
    return this.actual.filas.map((fila) => ({
      ...fila,
      recibida: fechaHora(fila.recibida),
      claseResultado:
        "resultado resultado_" + (CLASES[fila.resultado] || "pendiente")
    }));
  }

  get hayFilas() {
    return this.filas.length > 0;
  }

  get sinFilas() {
    return Boolean(this.actual) && this.filas.length === 0;
  }

  get rango() {
    if (!this.hayFilas) {
      return "";
    }
    const inicio = this.indice * TAMANO_PAGINA + 1;
    return "Lecturas " + inicio + " a " + (inicio + this.filas.length - 1);
  }

  get fueraDeVentana() {
    return Boolean(this.paginas[0] && this.paginas[0].fueraDeVentana);
  }

  get textoVentana() {
    return (
      "La bitácora guarda " +
      VENTANA_DIAS +
      " días de lecturas aplicadas y atrasadas. Las que abrieron, escalaron o normalizaron el incidente están siempre en «Señales del caso»."
    );
  }

  get sinAnterior() {
    return this.cargando || this.indice === 0;
  }

  get sinSiguiente() {
    return this.cargando || !this.actual || !this.actual.hayMas;
  }

  handleAlternar() {
    this.abierta = !this.abierta;
    if (this.abierta && this.paginas.length === 0) {
      this.cargar(0, null, []);
    }
  }

  handlePrimera() {
    this.indice = 0;
  }

  handleAnterior() {
    if (this.indice > 0) {
      this.indice -= 1;
    }
  }

  handleSiguiente() {
    const siguiente = this.indice + 1;
    if (this.paginas[siguiente]) {
      this.indice = siguiente;
      return;
    }
    this.cargar(
      siguiente,
      this.actual.siguienteHasta,
      this.actual.siguienteVistos
    );
  }

  handleSenal(event) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        objectApiName: "Senal__c",
        actionName: "view"
      }
    });
  }

  async cargar(indice, hasta, vistos) {
    this.cargando = true;
    this.error = undefined;
    try {
      const respuesta = await pagina({
        casoId: this.recordId,
        hasta,
        vistos
      });
      if (!respuesta) {
        this.sinAcceso = true;
        return;
      }
      const paginas = [...this.paginas];
      paginas[indice] = respuesta;
      this.paginas = paginas;
      this.indice = indice;
    } catch {
      this.error = "No se pudieron cargar las lecturas del periodo.";
    } finally {
      this.cargando = false;
    }
  }
}
