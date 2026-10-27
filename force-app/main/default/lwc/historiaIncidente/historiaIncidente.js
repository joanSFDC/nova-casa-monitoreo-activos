import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { updateRecord } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import {
  registerRefreshHandler,
  unregisterRefreshHandler
} from "lightning/refresh";
import LOCALE from "@salesforce/i18n/locale";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import PUEDE_COMPLETAR from "@salesforce/customPermission/Nova_Casa_Registrar_Intervencion";
import historia from "@salesforce/apex/HistoriaIncidenteControlador.historia";

export const TOPE_INICIAL = 10;
export const TOPE_MAXIMO = 100;

const TIPOS = {
  apertura: { clase: "evento evento_apertura", nombre: "Apertura" },
  cambio: { clase: "evento evento_cambio", nombre: "Cambio" },
  critico: { clase: "evento evento_critico", nombre: "Cambio crítico" },
  intervencion: {
    clase: "evento evento_intervencion",
    nombre: "Intervención cerrada"
  }
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

// Una fecha sin hora llega como medianoche UTC; en otra zona se correria un dia.
function fechaSola(valor) {
  if (!valor) {
    return "";
  }
  return new Intl.DateTimeFormat(LOCALE, {
    dateStyle: "short",
    timeZone: "UTC"
  }).format(new Date(valor));
}

/**
 * Lo que se ha hecho y lo que ha cambiado en el incidente: las intervenciones
 * abiertas arriba y, debajo, una línea de tiempo del más reciente al más viejo.
 */
export default class HistoriaIncidente extends LightningElement {
  @api recordId;

  tope = TOPE_INICIAL;
  respuesta;
  ultimos;
  idRefresco;
  completando = false;

  // Al pedir toda la historia se sigue viendo la anterior mientras llega.
  @wire(historia, { casoId: "$recordId", tope: "$tope" })
  cargar(respuesta) {
    this.respuesta = respuesta;
    if (respuesta.data !== undefined) {
      this.ultimos = respuesta.data;
    }
  }

  connectedCallback() {
    this.idRefresco = registerRefreshHandler(this, this.refrescar);
  }

  disconnectedCallback() {
    unregisterRefreshHandler(this.idRefresco);
  }

  refrescar() {
    return refreshApex(this.respuesta);
  }

  get datos() {
    return this.ultimos || null;
  }

  get cargando() {
    return this.ultimos === undefined && !this.error;
  }

  get error() {
    return this.respuesta && this.respuesta.error
      ? "No se pudo cargar la historia del incidente."
      : null;
  }

  get abiertas() {
    if (!this.datos) {
      return [];
    }
    return this.datos.abiertas.map((intervencion) => ({
      ...intervencion,
      responsable: intervencion.responsable || "Sin responsable",
      fechaLimite: intervencion.fechaLimite
        ? fechaSola(intervencion.fechaLimite)
        : "Sin fecha",
      prioridad: intervencion.prioridad || "Sin prioridad",
      etiquetaCompletar: "Completar «" + intervencion.asunto + "»"
    }));
  }

  // Quien registra intervenciones es quien las da por terminadas.
  get puedeCompletar() {
    return Boolean(PUEDE_COMPLETAR);
  }

  get tituloAbiertas() {
    return "Intervenciones abiertas (" + this.abiertas.length + ")";
  }

  get hayAbiertas() {
    return this.abiertas.length > 0;
  }

  get eventos() {
    if (!this.datos) {
      return [];
    }
    return this.datos.eventos.map((evento) => {
      const tipo = TIPOS[evento.tipo] || TIPOS.cambio;
      return {
        clave: evento.clave,
        clase: tipo.clase,
        tipo: tipo.nombre,
        cuando: fechaHora(evento.fecha),
        esCambio: Boolean(evento.campo),
        campo: evento.campo,
        antes: evento.antes || "sin valor",
        despues: evento.despues || "sin valor",
        texto: evento.texto,
        quien: evento.quien || ""
      };
    });
  }

  get hayEventos() {
    return this.eventos.length > 0;
  }

  get puedeVerTodo() {
    return Boolean(this.datos && this.datos.hayMas && this.tope < TOPE_MAXIMO);
  }

  get recortada() {
    return Boolean(this.datos && this.datos.hayMas && this.tope >= TOPE_MAXIMO);
  }

  get textoRecortada() {
    return (
      "Se muestran los " + TOPE_MAXIMO + " cambios más recientes del incidente."
    );
  }

  // Un espacio al final de una linea de la plantilla se pierde al compilarla.
  get conector() {
    return " a ";
  }

  handleVerTodo() {
    this.tope = TOPE_MAXIMO;
  }

  async handleCompletar(event) {
    const id = event.currentTarget.dataset.id;
    this.completando = true;
    try {
      await updateRecord({ fields: { Id: id, Status: "Completed" } });
      this.avisar("success", "Intervención completada.");
      await refreshApex(this.respuesta);
    } catch {
      this.avisar("error", "No se pudo completar la intervención.");
    } finally {
      this.completando = false;
    }
  }

  avisar(variante, mensaje) {
    this.dispatchEvent(
      new ShowToastEvent({ title: mensaje, variant: variante })
    );
  }
}
