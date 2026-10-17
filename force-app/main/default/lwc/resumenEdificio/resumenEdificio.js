import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import edificio from "@salesforce/apex/ResumenRegistroControlador.edificio";

const COMUNICACION = {
  LOST: "perdida",
  RESTORED: "recuperada",
  HEALTHY: "enlinea"
};

const CONTEOS = [
  {
    campo: "criticos",
    singular: "crítico",
    plural: "críticos",
    clase: "critico"
  },
  {
    campo: "advertencias",
    singular: "advertencia",
    plural: "advertencias",
    clase: "advertencia"
  },
  {
    campo: "normales",
    singular: "normal",
    plural: "normales",
    clase: "normal"
  },
  {
    campo: "sinComunicacion",
    singular: "sin comunicación",
    plural: "sin comunicación",
    clase: "perdida"
  }
];

/**
 * El edificio en una tarjeta: cuántos equipos hay en cada severidad, cómo
 * está cada uno y qué incidentes siguen abiertos, sin ir activo por activo.
 */
export default class ResumenEdificio extends NavigationMixin(LightningElement) {
  @api recordId;

  @wire(edificio, { edificioId: "$recordId" })
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
      ? "No se pudo cargar el resumen del edificio."
      : null;
  }

  get lugar() {
    return [this.datos.ciudad, this.datos.region].filter(Boolean).join(" · ");
  }

  get conteos() {
    return CONTEOS.map((conteo) => {
      const numero = this.datos[conteo.campo] || 0;
      return {
        clave: conteo.campo,
        clase:
          "conteo " + (numero > 0 ? "conteo_" + conteo.clase : "conteo_vacio"),
        texto: numero + " " + (numero === 1 ? conteo.singular : conteo.plural)
      };
    });
  }

  get equipos() {
    return (this.datos.equipos || []).map((equipo) => ({
      ...equipo,
      claseComunicacion:
        "comunicacion comunicacion_" +
        (COMUNICACION[equipo.comunicacionEstado] || "desconocida")
    }));
  }

  get hayEquipos() {
    return this.equipos.length > 0;
  }

  get casos() {
    return (this.datos.casos || []).map((caso) => ({
      ...caso,
      detalle: ["Prioridad " + caso.prioridad]
        .concat(
          caso.ultimaLectura ? ["última lectura " + caso.ultimaLectura] : []
        )
        .join(" · ")
    }));
  }

  get hayCasos() {
    return this.casos.length > 0;
  }

  handleActivo(event) {
    this.navegar(event.currentTarget.dataset.id, "Activo__c");
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
