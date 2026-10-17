import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import incidente from "@salesforce/apex/ResumenRegistroControlador.incidente";

function fecha(valor) {
  if (!valor) {
    return "";
  }
  return new Intl.DateTimeFormat(LOCALE, {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: TIME_ZONE
  }).format(new Date(valor));
}

/**
 * Lo que una persona necesita del incidente sin salir de él: el equipo, la
 * lectura que lo abrió, la última que lo cambió y cómo está ahora.
 */
export default class ResumenIncidente extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  @wire(incidente, { caseId: "$recordId" })
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
      ? "No se pudo cargar el resumen del incidente."
      : null;
  }

  get equipo() {
    return this.datos ? this.datos.equipo : null;
  }

  get detalleEquipo() {
    if (!this.equipo) {
      return "";
    }
    return [this.equipo.tipoEtiqueta, this.equipo.codigo]
      .filter(Boolean)
      .join(" · ");
  }

  get columnas() {
    if (!this.datos) {
      return [];
    }
    const { apertura, ultima, ahora } = this.datos;
    return [
      this.columna(
        "apertura",
        "Lo abrió",
        apertura,
        apertura && fecha(apertura.fecha)
      ),
      this.columna(
        "ultima",
        "Último cambio",
        ultima,
        ultima && fecha(ultima.fecha)
      ),
      this.columna(
        "ahora",
        "Ahora",
        ahora && {
          texto: ahora.lectura,
          severidad: ahora.severidad,
          severidadEtiqueta: ahora.severidadEtiqueta
        },
        ahora && ahora.antiguedad
      )
    ];
  }

  columna(clave, titulo, lectura, detalle) {
    return {
      clave,
      titulo,
      tiene: Boolean(lectura && lectura.texto),
      texto: lectura ? lectura.texto : null,
      severidad: lectura ? lectura.severidad : null,
      severidadEtiqueta: lectura ? lectura.severidadEtiqueta : null,
      detalle: detalle || ""
    };
  }

  get mostrarNormalizado() {
    return Boolean(this.datos && this.datos.normalizado && !this.datos.cerrado);
  }

  get textoNormalizado() {
    const cuando = this.datos ? fecha(this.datos.normalizadoEn) : "";
    return (
      "El equipo volvió a lo normal" +
      (cuando ? " el " + cuando : "") +
      ". El caso sigue abierto hasta que coordinación lo verifique y lo cierre."
    );
  }

  handleEquipo() {
    this.navegar(this.equipo.activoId, "Activo__c");
  }

  handleEdificio() {
    this.navegar(this.equipo.edificioId, "Edificio__c");
  }

  navegar(recordId, objectApiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, objectApiName, actionName: "view" }
    });
  }
}
