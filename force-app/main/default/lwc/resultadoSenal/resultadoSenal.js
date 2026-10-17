import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  getFieldDisplayValue
} from "lightning/uiRecordApi";
import RESULTADO from "@salesforce/schema/Senal__c.Resultado__c";
import MOTIVO from "@salesforce/schema/Senal__c.Motivo__c";
import REINTENTABLE from "@salesforce/schema/Senal__c.Reintentable__c";
import ENTREGAS from "@salesforce/schema/Senal__c.Entregas__c";

const CAMPOS = [RESULTADO, MOTIVO, REINTENTABLE, ENTREGAS];

const RESULTADOS = {
  Aplicado: {
    clase: "aplicado",
    explicacion:
      "Se procesó y actualizó el estado actual del equipo. Si cambió la severidad de un incidente abierto, quedó registrada en el caso."
  },
  Pendiente: {
    clase: "pendiente",
    explicacion:
      "Llegó y se publicó, pero el procesamiento todavía no la resuelve. Si lleva más de una hora, aparece en la vista Atascadas."
  },
  Atrasado: {
    clase: "atrasado",
    explicacion:
      "Llegó después de una lectura más nueva del mismo equipo y medición. Se guarda como evidencia y no cambia el estado actual."
  },
  Conflicto: {
    clase: "conflicto",
    explicacion:
      "Llegó otra vez con el mismo identificador y otro contenido. Se conserva la primera versión y hace falta que una persona lo revise."
  },
  Rechazado: {
    clase: "rechazado",
    explicacion:
      "No pasó la validación: el motivo dice por qué. No llegó al estado actual ni abrió incidentes."
  },
  Fallido: {
    clase: "fallido",
    explicacion:
      "Falló al guardarse o al procesarse por un error del sistema. Se puede volver a procesar."
  },
  Duplicado: {
    clase: "pendiente",
    explicacion: "Un reenvío del mismo mensaje."
  }
};

/**
 * Qué pasó con la señal, en color y en palabras, con el motivo y si es seguro
 * volver a procesarla. Lee los campos con LDS: quien no los ve, no los recibe.
 */
export default class ResultadoSenal extends LightningElement {
  @api recordId;

  @wire(getRecord, { recordId: "$recordId", fields: CAMPOS })
  registro;

  get datos() {
    return this.registro && this.registro.data ? this.registro.data : null;
  }

  get resultado() {
    return getFieldValue(this.datos, RESULTADO);
  }

  get configuracion() {
    return (
      RESULTADOS[this.resultado] || { clase: "pendiente", explicacion: "" }
    );
  }

  get claseResultado() {
    return "resultado resultado_" + this.configuracion.clase;
  }

  get etiquetaResultado() {
    return getFieldDisplayValue(this.datos, RESULTADO) || this.resultado;
  }

  get explicacion() {
    return this.configuracion.explicacion;
  }

  get motivo() {
    return (
      getFieldDisplayValue(this.datos, MOTIVO) ||
      getFieldValue(this.datos, MOTIVO)
    );
  }

  get reintentable() {
    return getFieldValue(this.datos, REINTENTABLE) === true;
  }

  get entregas() {
    const entregas = getFieldValue(this.datos, ENTREGAS);
    if (!entregas || entregas <= 1) {
      return null;
    }
    return "Llegó " + entregas + " veces";
  }
}
