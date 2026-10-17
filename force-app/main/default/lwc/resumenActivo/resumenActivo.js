import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import activo from "@salesforce/apex/ResumenRegistroControlador.activo";

const COMUNICACION = {
  LOST: "perdida",
  RESTORED: "recuperada",
  HEALTHY: "enlinea"
};

/**
 * El activo en una tarjeta: cómo está cada medición, sus incidentes abiertos y
 * los límites que se le aplican, sin ir al edificio, al estado ni al umbral.
 */
export default class ResumenActivo extends NavigationMixin(LightningElement) {
  @api recordId;

  @wire(activo, { activoId: "$recordId" })
  resumen;

  get datos() {
    return this.resumen && this.resumen.data ? this.resumen.data : null;
  }

  get cargando() {
    return (
      !this.resumen || (this.resumen.data === undefined && !this.resumen.error)
    );
  }

  get error() {
    return this.resumen && this.resumen.error
      ? "No se pudo cargar el resumen del activo."
      : null;
  }

  get detalleEquipo() {
    const equipo = this.datos.equipo;
    return [equipo.tipoEtiqueta, equipo.codigo].filter(Boolean).join(" · ");
  }

  get mediciones() {
    return (this.datos.mediciones || []).map((medicion) => ({
      ...medicion,
      claseComunicacion:
        "comunicacion comunicacion_" +
        (COMUNICACION[medicion.comunicacionEstado] || "desconocida")
    }));
  }

  get hayMediciones() {
    return this.mediciones.length > 0;
  }

  get casos() {
    return this.datos.casos || [];
  }

  get hayCasos() {
    return this.casos.length > 0;
  }

  get limites() {
    return (this.datos.limites || []).map((limite) => ({
      ...limite,
      clave: limite.tipoMedicion
    }));
  }

  get hayLimites() {
    return this.limites.length > 0;
  }

  handleEdificio() {
    this.navegar(this.datos.equipo.edificioId, "Edificio__c");
  }

  handleCaso(event) {
    this.navegar(event.currentTarget.dataset.id, "Case");
  }

  navegar(recordId, objectApiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, objectApiName, actionName: "view" }
    });
  }
}
