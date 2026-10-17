import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import LOCALE from "@salesforce/i18n/locale";
import TIPO_MEDICION from "@salesforce/schema/Umbral__c.Tipo_Medicion__c";
import UNIDAD from "@salesforce/schema/Umbral__c.Unidad__c";
import DECIMALES from "@salesforce/schema/Umbral__c.Decimales__c";
import CRITICO_BAJO from "@salesforce/schema/Umbral__c.Critico_Bajo__c";
import ADVERTENCIA_BAJO from "@salesforce/schema/Umbral__c.Advertencia_Bajo__c";
import ADVERTENCIA_ALTO from "@salesforce/schema/Umbral__c.Advertencia_Alto__c";
import CRITICO_ALTO from "@salesforce/schema/Umbral__c.Critico_Alto__c";
import MINUTOS_ADVERTENCIA from "@salesforce/schema/Umbral__c.Minutos_Advertencia__c";
import MINUTOS_CRITICO from "@salesforce/schema/Umbral__c.Minutos_Critico__c";

const CAMPOS = [
  TIPO_MEDICION,
  UNIDAD,
  DECIMALES,
  CRITICO_BAJO,
  ADVERTENCIA_BAJO,
  ADVERTENCIA_ALTO,
  CRITICO_ALTO,
  MINUTOS_ADVERTENCIA,
  MINUTOS_CRITICO
];

const UNIDADES = {
  BAR: "bar",
  CELSIUS: "°C",
  LITER_PER_15_MIN: "L/15 min",
  KWH_PER_15_MIN: "kWh/15 min"
};

function hay(valor) {
  return valor !== null && valor !== undefined && valor !== "";
}

/**
 * Cómo clasifica un umbral, dibujado como una regla de bandas. Sirve en la
 * página del umbral (lo lee con LDS) y dentro del resumen del activo (recibe
 * el límite ya armado). Las fronteras son las de ClasificacionServicio: crítico
 * si llega al crítico, advertencia si llega a la advertencia, normal entre las dos.
 */
export default class BandasUmbral extends LightningElement {
  @api recordId;
  @api limite;
  @api compacto = false;

  @wire(getRecord, { recordId: "$idParaLeer", fields: CAMPOS })
  registro;

  get idParaLeer() {
    return this.limite ? undefined : this.recordId;
  }

  get datos() {
    if (this.limite) {
      return this.limite;
    }
    const record = this.registro && this.registro.data;
    if (!record) {
      return null;
    }
    const unidad = getFieldValue(record, UNIDAD);
    return {
      tipoMedicion: getFieldValue(record, TIPO_MEDICION),
      unidad: UNIDADES[unidad] || unidad,
      decimales: getFieldValue(record, DECIMALES) || 0,
      criticoBajo: getFieldValue(record, CRITICO_BAJO),
      advertenciaBajo: getFieldValue(record, ADVERTENCIA_BAJO),
      advertenciaAlto: getFieldValue(record, ADVERTENCIA_ALTO),
      criticoAlto: getFieldValue(record, CRITICO_ALTO),
      minutosAdvertencia: getFieldValue(record, MINUTOS_ADVERTENCIA),
      minutosCritico: getFieldValue(record, MINUTOS_CRITICO)
    };
  }

  get esCamara() {
    return Boolean(
      this.datos && this.datos.tipoMedicion === "CAMERA_CONNECTIVITY"
    );
  }

  numero(valor) {
    const lugares = this.datos.decimales || 0;
    const texto = new Intl.NumberFormat(LOCALE, {
      minimumFractionDigits: lugares,
      maximumFractionDigits: lugares
    }).format(valor);
    return this.datos.unidad ? texto + " " + this.datos.unidad : texto;
  }

  get bandas() {
    const d = this.datos;
    if (!d) {
      return [];
    }
    const bandas = [];
    if (this.esCamara) {
      if (hay(d.minutosAdvertencia)) {
        bandas.push(
          this.banda(
            "normal",
            "Normal",
            "menos de " + d.minutosAdvertencia + " min sin señal"
          )
        );
        bandas.push(
          this.banda(
            "advertencia",
            "Advertencia",
            "desde " + d.minutosAdvertencia + " min"
          )
        );
      }
      if (hay(d.minutosCritico)) {
        bandas.push(
          this.banda("critico", "Crítico", "desde " + d.minutosCritico + " min")
        );
      }
      return this.conClave(bandas);
    }
    if (hay(d.criticoBajo)) {
      bandas.push(
        this.banda("critico", "Crítico", "hasta " + this.numero(d.criticoBajo))
      );
    }
    if (hay(d.advertenciaBajo)) {
      bandas.push(
        this.banda(
          "advertencia",
          "Advertencia",
          "hasta " + this.numero(d.advertenciaBajo)
        )
      );
    }
    bandas.push(this.banda("normal", "Normal", this.textoNormal(d)));
    if (hay(d.advertenciaAlto)) {
      bandas.push(
        this.banda(
          "advertencia",
          "Advertencia",
          "desde " + this.numero(d.advertenciaAlto)
        )
      );
    }
    if (hay(d.criticoAlto)) {
      bandas.push(
        this.banda("critico", "Crítico", "desde " + this.numero(d.criticoAlto))
      );
    }
    return this.conClave(bandas);
  }

  conClave(bandas) {
    return bandas.map((banda, indice) => ({ ...banda, clave: String(indice) }));
  }

  textoNormal(d) {
    const bajo = hay(d.advertenciaBajo) ? d.advertenciaBajo : d.criticoBajo;
    const alto = hay(d.advertenciaAlto) ? d.advertenciaAlto : d.criticoAlto;
    if (hay(bajo) && hay(alto)) {
      return "más de " + this.numero(bajo) + " y menos de " + this.numero(alto);
    }
    if (hay(alto)) {
      return "menos de " + this.numero(alto);
    }
    if (hay(bajo)) {
      return "más de " + this.numero(bajo);
    }
    return "sin fronteras";
  }

  banda(tipo, nombre, rango) {
    return {
      clase: "banda banda_" + tipo,
      nombre,
      rango
    };
  }

  get titulo() {
    return this.compacto ? null : "Cómo clasifica este umbral";
  }

  get claseContenedor() {
    return this.compacto ? "bandas bandas_compacto" : "bandas tarjeta";
  }
}
